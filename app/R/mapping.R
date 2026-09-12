# mapping.R — build/auto-suggest field mappings, value recodes, and persist
# reusable mapping templates as JSON.
#
# A mapping template (one JSON file) bundles everything needed to reproduce a
# conversion on a new export with the same REDCap structure:
#   list(binding, map, recode, datefmt)

suppressPackageStartupMessages(library(jsonlite))

el_norm <- function(x) gsub("[^a-z0-9]", "", tolower(as.character(x %||% "")))

# domain synonyms: ELSO leaf name (normalized) -> regex over redcap name/label
EL_SYNONYMS <- list(
  uniqueid    = "record|study.?id|patient.?id|mrn|uniqueid",
  birthdate   = "dob|birth|dateofbirth",
  sex         = "sex|gender",
  racecode    = "race|ethnic",
  admitdate   = "admit|admission.?date",
  dischargedate = "discharge.?date",
  deathdate   = "death|expired|died",
  runno       = "run.?(no|number)|ecmo.?run",
  supporttype = "support.?type|ecls.?type|mode.?of.?support",
  completedby = "completed.?by|entered.?by|author",
  diagnosiscode = "diag|icd|dx",
  complicationcode = "complication|comp.?code",
  primary     = "primary")

# Suggest field mappings from REDCap dictionary to ELSO leaves.
el_auto_suggest_map <- function(cat, dictionary) {
  lv <- el_leaves(cat)
  fld_norm <- el_norm(dictionary$field)
  lbl_norm <- el_norm(dictionary$label)
  map <- list()
  for (i in seq_len(nrow(lv))) {
    nm <- lv$name[i]; nn <- el_norm(nm); hit <- NA_integer_
    # 1) exact field-name match
    j <- which(fld_norm == nn); if (length(j)) hit <- j[1]
    # 2) synonym regex over field or label
    if (is.na(hit) && !is.null(EL_SYNONYMS[[nn]])) {
      rx <- EL_SYNONYMS[[nn]]
      j <- which(grepl(rx, dictionary$field, ignore.case = TRUE) |
                 grepl(rx, dictionary$label, ignore.case = TRUE))
      if (length(j)) hit <- j[1]
    }
    # 3) label contains the leaf name
    if (is.na(hit) && nchar(nn) >= 4) {
      j <- which(grepl(nn, lbl_norm, fixed = TRUE)); if (length(j)) hit <- j[1]
    }
    if (!is.na(hit)) map[[lv$path[i]]] <- list(source = dictionary$field[hit])
  }
  map
}

# Auto value-crosswalk for coded leaves whose REDCap choice labels match ELSO
# code-list labels. Returns recode list: path -> named vec (redcapCode -> elsoCode).
el_auto_recode <- function(cat, parsed, map) {
  lv <- el_leaves(cat); recode <- list()
  for (path in names(map)) {
    li <- match(path, lv$path); if (is.na(li)) next
    if (!isTRUE(lv$has_codes[li])) next
    elso_cl <- el_codelist(cat, lv[li, ])
    src <- map[[path]]$source
    rc_cl <- parsed$choices[[src]]
    if (is.null(elso_cl) || is.null(rc_cl)) next
    key <- setNames(elso_cl$code, el_norm(elso_cl$label))
    v <- setNames(character(0), character(0))
    for (k in seq_len(nrow(rc_cl))) {
      nm <- el_norm(rc_cl$label[k])
      if (nm %in% names(key) && !is.na(key[[nm]]))
        v[rc_cl$code[k]] <- key[[nm]]
    }
    if (length(v)) recode[[path]] <- v
  }
  recode
}

# default date formats: mark temporal leaves; input auto, target from catalogue
el_default_datefmt <- function(cat, map) {
  lv <- el_leaves(cat); df <- list()
  for (path in names(map)) {
    li <- match(path, lv$path); if (is.na(li)) next
    if (lv$kind[li] %in% c("date", "datetime"))
      df[[path]] <- list(input = "auto", target = lv$kind[li])
  }
  df
}

el_save_mapping <- function(template, path) {
  jsonlite::write_json(template, path, auto_unbox = TRUE, pretty = TRUE, null = "null")
  path
}
el_load_mapping <- function(path) {
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}
