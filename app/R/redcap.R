# redcap.R — read a REDCap export into a field dictionary + long records.
#
# Two input paths:
#   * ODM XML  (REDCap "Export -> CDISC ODM"): metadata (ItemDef/CodeList/FormDef)
#     AND clinical data in one file. Preferred; self-describing.
#   * CSV      (records CSV [+ optional data-dictionary CSV]).
#
# Output (both paths) is a common shape:
#   list(dictionary = data.frame(field,label,form,data_type,coded,choices_key),
#        choices    = named list  field -> data.frame(code,label),
#        records    = data.frame  one row per (subject,event,form,instance) with
#                     meta cols .subject/.event/.form/.instance + one col per field,
#        forms      = character vector of form/instrument names)

suppressPackageStartupMessages(library(xml2))

# ---- ODM XML ---------------------------------------------------------------

el_read_redcap_odm <- function(path) {
  doc <- read_xml(path)
  xml_ns_strip(doc)                      # drop namespaces -> plain xpath

  # metadata
  item_defs <- xml_find_all(doc, "//MetaDataVersion/ItemDef")
  dict <- data.frame(
    field     = xml_attr(item_defs, "OID"),
    label     = xml_attr(item_defs, "Name"),
    data_type = xml_attr(item_defs, "DataType"),
    stringsAsFactors = FALSE)
  # nicer label if a Question/TranslatedText is present
  q <- vapply(item_defs, function(n) {
    tt <- xml_find_first(n, "./Question/TranslatedText")
    if (is.na(tt)) NA_character_ else xml_text(tt)
  }, character(1))
  dict$label <- ifelse(!is.na(q) & nzchar(q), q, dict$label)

  # code lists
  choices <- list()
  cls <- xml_find_all(doc, "//MetaDataVersion/CodeList")
  cl_by_oid <- list()
  for (cl in cls) {
    oid <- xml_attr(cl, "OID")
    items <- xml_find_all(cl, "./CodeListItem")
    cv <- xml_attr(items, "CodedValue")
    dec <- vapply(items, function(n) {
      tt <- xml_find_first(n, "./Decode/TranslatedText")
      if (is.na(tt)) NA_character_ else xml_text(tt)
    }, character(1))
    cl_by_oid[[oid]] <- data.frame(code = cv, label = dec, stringsAsFactors = FALSE)
  }
  # map ItemDef -> CodeListRef
  dict$coded <- FALSE
  dict$choices_key <- NA_character_
  for (i in seq_along(item_defs)) {
    ref <- xml_find_first(item_defs[[i]], "./CodeListRef")
    if (!is.na(ref)) {
      oid <- xml_attr(ref, "CodeListOID")
      if (!is.null(cl_by_oid[[oid]])) {
        dict$coded[i] <- TRUE
        dict$choices_key[i] <- dict$field[i]
        choices[[dict$field[i]]] <- cl_by_oid[[oid]]
      }
    }
  }
  # ItemDef -> owning form (via FormDef/ItemGroupRef/ItemGroupDef/ItemRef)
  form_of_item <- el_odm_item_forms(doc)
  dict$form <- unname(form_of_item[dict$field]); dict$form[is.na(dict$form)] <- ""

  # clinical data -> long records (translate FormOID -> friendly Name)
  records <- el_odm_records(doc, dict$field)
  oid2name <- c()
  for (fd in xml_find_all(doc, "//MetaDataVersion/FormDef")) {
    nm <- xml_attr(fd, "Name"); if (is.na(nm)) nm <- xml_attr(fd, "OID")
    oid2name[xml_attr(fd, "OID")] <- nm
  }
  mapped <- unname(oid2name[records$.form])
  records$.form <- ifelse(is.na(mapped), records$.form, mapped)
  forms <- unique(c(dict$form[nzchar(dict$form)], unique(records$.form)))
  list(dictionary = dict, choices = choices, records = records,
       forms = sort(unique(forms[nzchar(forms)])))
}

# map each ItemOID to its form name using the metadata graph
el_odm_item_forms <- function(doc) {
  out <- c()
  ig_items <- list()   # ItemGroupOID -> item OIDs
  for (ig in xml_find_all(doc, "//MetaDataVersion/ItemGroupDef")) {
    oid <- xml_attr(ig, "OID")
    ig_items[[oid]] <- xml_attr(xml_find_all(ig, "./ItemRef"), "ItemOID")
  }
  for (fd in xml_find_all(doc, "//MetaDataVersion/FormDef")) {
    fname <- xml_attr(fd, "Name"); if (is.na(fname)) fname <- xml_attr(fd, "OID")
    for (oid in xml_attr(xml_find_all(fd, "./ItemGroupRef"), "ItemGroupOID"))
      for (it in ig_items[[oid]] %||% character(0))
        out[it] <- fname
  }
  out
}

el_odm_records <- function(doc, all_fields) {
  rows <- list()
  for (sd in xml_find_all(doc, "//ClinicalData/SubjectData")) {
    subj <- xml_attr(sd, "SubjectKey")
    events <- xml_find_all(sd, "./StudyEventData")
    if (length(events) == 0) events <- list(sd)   # flat: no events
    for (ev in events) {
      evoid <- if (inherits(ev, "xml_node")) xml_attr(ev, "StudyEventOID") else NA_character_
      forms <- xml_find_all(ev, "./FormData")
      if (length(forms) == 0) forms <- xml_find_all(ev, ".//FormData")
      for (fd in forms) {
        foid <- xml_attr(fd, "FormOID")
        inst <- xml_attr(fd, "FormRepeatKey")
        vals <- c()
        for (idn in xml_find_all(fd, ".//ItemData")) {
          oid <- xml_attr(idn, "ItemOID"); v <- xml_attr(idn, "Value")
          if (!is.na(oid)) vals[oid] <- v %||% ""
        }
        rec <- c(.subject = subj, .event = evoid %||% "",
                 .form = foid %||% "", .instance = inst %||% "1")
        rows[[length(rows) + 1L]] <- c(as.list(rec), as.list(vals))
      }
    }
  }
  el_rows_to_df(rows, meta = c(".subject", ".event", ".form", ".instance"),
                fields = all_fields)
}

# combine list-of-named-lists into a character data.frame with a stable column set
el_rows_to_df <- function(rows, meta, fields) {
  cols <- unique(c(meta, fields,
                   unique(unlist(lapply(rows, names)))))
  cols <- cols[!duplicated(cols)]
  m <- matrix(NA_character_, nrow = length(rows), ncol = length(cols),
              dimnames = list(NULL, cols))
  for (i in seq_along(rows)) {
    r <- rows[[i]]
    for (nm in names(r)) m[i, nm] <- as.character(r[[nm]] %||% NA)
  }
  as.data.frame(m, stringsAsFactors = FALSE, check.names = FALSE)
}

# ---- CSV -------------------------------------------------------------------

el_read_redcap_csv <- function(records_path, dict_path = NULL) {
  recs <- utils::read.csv(records_path, stringsAsFactors = FALSE,
                          colClasses = "character", check.names = FALSE,
                          na.strings = c("NA"))
  # meta: use REDCap's record_id + redcap_event_name + redcap_repeat_* if present
  subj_col <- intersect(c("record_id", "study_id", "id"), names(recs))[1]
  recs$.subject  <- if (!is.na(subj_col)) recs[[subj_col]] else as.character(seq_len(nrow(recs)))
  recs$.event    <- if ("redcap_event_name" %in% names(recs)) recs$redcap_event_name else ""
  recs$.form     <- if ("redcap_repeat_instrument" %in% names(recs)) recs$redcap_repeat_instrument else ""
  recs$.instance <- if ("redcap_repeat_instance" %in% names(recs)) recs$redcap_repeat_instance else "1"

  choices <- list(); coded <- rep(FALSE, 0)
  dict <- data.frame(field = setdiff(names(recs), c(".subject",".event",".form",".instance")),
                     stringsAsFactors = FALSE)
  dict$label <- dict$field; dict$data_type <- "text"; dict$form <- ""
  dict$coded <- FALSE; dict$choices_key <- NA_character_

  if (!is.null(dict_path) && file.exists(dict_path)) {
    dd <- utils::read.csv(dict_path, stringsAsFactors = FALSE, check.names = FALSE,
                          colClasses = "character")
    names(dd) <- tolower(gsub("[^a-z]+", "_", tolower(names(dd))))
    fcol <- names(dd)[grepl("variable|field_name", names(dd))][1]
    lcol <- names(dd)[grepl("field_label|label", names(dd))][1]
    ccol <- names(dd)[grepl("choices|calculations|slider", names(dd))][1]
    formcol <- names(dd)[grepl("form_name|instrument", names(dd))][1]
    for (i in seq_len(nrow(dd))) {
      f <- dd[[fcol]][i]; j <- match(f, dict$field); if (is.na(j)) next
      if (!is.na(lcol)) dict$label[j] <- dd[[lcol]][i]
      if (!is.na(formcol)) dict$form[j] <- dd[[formcol]][i] %||% ""
      if (!is.na(ccol) && !el_blank(dd[[ccol]][i]) && grepl("\\|", dd[[ccol]][i])) {
        ch <- el_parse_redcap_choices(dd[[ccol]][i])
        if (!is.null(ch)) { dict$coded[j] <- TRUE; dict$choices_key[j] <- f; choices[[f]] <- ch }
      }
    }
  }
  list(dictionary = dict, choices = choices, records = recs,
       forms = sort(unique(dict$form[nzchar(dict$form)])))
}

# "1, Male | 2, Female" -> data.frame(code,label)
el_parse_redcap_choices <- function(s) {
  parts <- trimws(unlist(strsplit(s, "|", fixed = TRUE)))
  code <- character(0); label <- character(0)
  for (p in parts) {
    kv <- trimws(sub(",", "\a", p))            # split on first comma only
    kv <- strsplit(kv, "\a", fixed = TRUE)[[1]]
    if (length(kv) >= 2) { code <- c(code, kv[1]); label <- c(label, kv[2]) }
  }
  if (!length(code)) return(NULL)
  data.frame(code = code, label = label, stringsAsFactors = FALSE)
}
