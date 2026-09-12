# grouping.R — collapse flat/longitudinal REDCap records into the nested
# Patient -> Hospitalization -> Run (+ run-level sub-collections) hierarchy the
# generator consumes.
#
# binding:
#   patient_key    column in records identifying the patient (default ".subject")
#   patient_form   instrument holding patient + hospitalization scalar fields
#                  (non-repeating); if "" use the patient's first record row
#   run_form       instrument = one row per ECMO run; if "" one run per patient
#   run_key_field  field whose value becomes RunNo / links sub-collections
#   subcollections named list: ELSO repeat_level path ->
#                     list(form = <instrument>, link_field = <field|NA>,
#                          key_field = <field|NA>)
#                     link_field links a row to its PARENT (a run, or a parent
#                     sub-collection instance); key_field identifies this row so
#                     nested (deeper) sub-collections can link back to it.
#
# Nesting: a sub-collection whose ELSO path is a descendant of another bound
#   sub-collection's path attaches to that parent's instances (e.g. a Cardiac
#   catheterisation's Diagnostics attach to each CardiacCath, not to the run).
#   The generator already walks arbitrary depth — it only needs each instance's
#   scope to carry its own `coll` for its children, which el_attach_subs builds.
#
# MVP simplifications (documented, extensible later):
#   * one Hospitalization per patient (patient_form row feeds it)
#   * a single PatientsRaces/Race sourced from the patient row
#   * a sub-collection with no link_field attaches to the FIRST parent instance
#     only (first run for run-level; first parent row for nested)

el_named_row <- function(df, i) {
  if (is.null(df) || nrow(df) == 0 || is.na(i)) return(setNames(character(0), character(0)))
  cols <- names(df)
  v <- as.character(unlist(df[i, cols, drop = TRUE]))
  setNames(v, cols)
}

el_rows_for <- function(records, form, patient_key, pid) {
  if (el_blank(form)) return(records[integer(0), , drop = FALSE])
  keep <- records$.form == form & records[[patient_key]] == pid
  records[which(keep), , drop = FALSE]
}

# For a set of sub-collection paths, map each to its nearest bound ancestor path
# (segment-wise prefix); "" means the parent is the run.
el_subs_parent_map <- function(paths) {
  segs <- lapply(paths, function(p) strsplit(p, "/", fixed = TRUE)[[1]])
  names(segs) <- paths
  out <- vapply(paths, function(p) {
    ps <- segs[[p]]
    anc <- paths[vapply(paths, function(c) {
      if (identical(c, p)) return(FALSE)
      cs <- segs[[c]]
      length(cs) < length(ps) && identical(ps[seq_along(cs)], cs)
    }, logical(1))]
    if (!length(anc)) return("")
    anc[which.max(nchar(anc))]   # longest ancestor = nearest
  }, character(1))
  setNames(out, paths)
}

# Build the `coll` list for one parent scope: for every sub-collection whose
# parent is `parent_path`, gather its rows (linked to parent_key_val), and
# recurse so each instance carries its own `coll` for deeper sub-collections.
el_attach_subs <- function(records, patient_key, pid, subs, parent_of,
                           parent_path, parent_key_val, first_instance) {
  coll <- list()
  child_paths <- names(subs)[parent_of[names(subs)] == parent_path]
  for (path in child_paths) {
    b <- subs[[path]]
    srows <- el_rows_for(records, b$form, patient_key, pid)
    if (nrow(srows) == 0) { coll[[path]] <- list(); next }
    if (!el_blank(b$link_field) && b$link_field %in% names(srows) &&
        !el_blank(parent_key_val)) {
      srows <- srows[srows[[b$link_field]] == parent_key_val, , drop = FALSE]
    } else if (!isTRUE(first_instance)) {
      srows <- srows[integer(0), , drop = FALSE]  # unlinked -> first parent only
    }
    coll[[path]] <- lapply(seq_len(nrow(srows)), function(i) {
      srow <- el_named_row(srows, i)
      kv <- if (!el_blank(b$key_field) && b$key_field %in% names(srow))
              srow[[b$key_field]] else NA_character_
      list(row  = srow,
           coll = el_attach_subs(records, patient_key, pid, subs, parent_of,
                                 path, kv, i == 1L))
    })
  }
  coll
}

el_build_hierarchy <- function(parsed, binding = list()) {
  records <- parsed$records
  patient_key <- binding$patient_key %||% ".subject"
  if (!patient_key %in% names(records)) patient_key <- ".subject"
  pids <- unique(records[[patient_key]]); pids <- pids[!is.na(pids)]

  patient_form <- binding$patient_form %||% ""
  run_form     <- binding$run_form %||% ""
  run_key      <- binding$run_key_field %||% ""
  subs         <- binding$subcollections %||% list()
  parent_of    <- if (length(subs)) el_subs_parent_map(names(subs))
                  else setNames(character(0), character(0))

  lapply(pids, function(pid) {
    # patient / hospitalization scalar row
    prows <- el_rows_for(records, patient_form, patient_key, pid)
    if (nrow(prows) == 0) {
      idx <- which(records[[patient_key]] == pid)[1]
      prow <- el_named_row(records, idx)
    } else prow <- el_named_row(prows, 1L)

    # runs
    rrows <- el_rows_for(records, run_form, patient_key, pid)
    if (nrow(rrows) == 0) run_rows <- list(prow)
    else run_rows <- lapply(seq_len(nrow(rrows)), function(i) el_named_row(rrows, i))

    runs <- lapply(seq_along(run_rows), function(ri) {
      rrow <- run_rows[[ri]]
      rkey_val <- if (!el_blank(run_key)) rrow[[run_key]] else NA_character_
      coll <- el_attach_subs(records, patient_key, pid, subs, parent_of,
                             parent_path = "", parent_key_val = rkey_val,
                             first_instance = ri == 1L)
      list(row = rrow, coll = coll)
    })

    list(row   = prow,
         races = list(list(row = prow)),
         hosps = list(list(row = prow, runs = runs)))
  })
}
