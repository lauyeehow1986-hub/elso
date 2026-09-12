# validate.R — semantic QC beyond the XSD. The XSD only checks structure and
# UniqueId length; codes, dates and numeric ranges live in the lookups workbook
# and are enforced here against the GENERATED document.
#
# Returns data.frame(path, value, issue, severity) with severity in
# c("error","warning"). errors should block a real submission; warnings are
# soft-range advisories.

suppressPackageStartupMessages(library(xml2))

# element path relative to PatientXML, built from ancestor LOCAL names.
# NB: xml_path() returns "/*/*[1]/..." for a default-namespaced document
# (libxml2 has no prefix to emit), so it cannot be used to recover element
# names. xml_name() returns the local name regardless of namespace, and the
# "*" wildcard in the XPath matches namespaced elements, so walk ancestors.
el_doc_path <- function(node) {
  anc <- xml2::xml_find_all(node, "ancestor-or-self::*")  # root -> node order
  nms <- xml2::xml_name(anc)
  nms <- nms[nms != "PatientList"]                        # drop the root
  paste(nms, collapse = "/")
}

el_num <- function(x) suppressWarnings(as.numeric(x))

el_semantic_check <- function(cat, doc) {
  lv <- el_leaves(cat)
  by_path <- split(seq_len(nrow(lv)), lv$path)
  issues <- list()
  add <- function(path, value, issue, severity)
    issues[[length(issues) + 1L]] <<- data.frame(
      path = path, value = value %||% "", issue = issue, severity = severity,
      stringsAsFactors = FALSE)

  nodes <- xml_find_all(doc, "//*[not(*)]")   # leaf elements only
  for (nd in nodes) {
    path <- el_doc_path(nd)
    idx <- by_path[[path]]; if (is.null(idx)) next
    row <- lv[idx[1], ]
    val <- xml_text(nd)

    if (identical(row$name, "UniqueId")) {
      n <- nchar(val)
      if (n < 10 || n > 20)
        add(path, val, sprintf("UniqueId must be 10-20 chars (got %d)", n), "error")
    }
    if (el_blank(val)) {
      # An empty required leaf is rejected by ELSO's import validator even
      # though the lenient XSD permits it, so flag it as an error.
      if (isTRUE(row$required) && !identical(row$name, "UniqueId"))
        add(path, "", "required field is empty (ELSO import will reject)", "error")
      next
    }
    # coded membership
    if (isTRUE(row$has_codes)) {
      cl <- el_codelist(cat, row)
      if (!is.null(cl) && !(val %in% cl$code))
        add(path, val, "value not in ELSO code list", "error")
    }
    # date parse (already ELSO-formatted here; sanity check). el_parse_time takes
    # a single format or "auto" (EL_DATE_FORMATS covers MM/DD/YYYY[ HH:MM]).
    if (row$kind %in% c("date", "datetime")) {
      ok <- !is.na(el_parse_time(val, "auto"))
      if (!ok) add(path, val, "unparseable date/datetime", "error")
    }
    # numeric hard range (best-effort key match)
    rg <- cat$ranges[[paste0(row$section, "::", row$name)]]
    if (!is.null(rg)) {
      x <- el_num(val)
      hmn <- el_num(rg$hard_min); hmx <- el_num(rg$hard_max)
      if (!is.na(x) && !is.na(hmn) && x < hmn)
        add(path, val, sprintf("below hard minimum %s", rg$hard_min), "warning")
      if (!is.na(x) && !is.na(hmx) && x > hmx)
        add(path, val, sprintf("above hard maximum %s", rg$hard_max), "warning")
    }
  }
  if (!length(issues))
    return(data.frame(path = character(0), value = character(0),
                      issue = character(0), severity = character(0)))
  do.call(rbind, issues)
}

el_validation_summary <- function(issues) {
  list(n_error = sum(issues$severity == "error"),
       n_warning = sum(issues$severity == "warning"),
       pass = sum(issues$severity == "error") == 0)
}
