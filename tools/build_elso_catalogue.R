# build_elso_catalogue.R — turn the official ELSO spec files into the app's
# bundled, R-readable catalogue. Run ONCE (offline) whenever ELSO ships a new
# schema. No network: reads docs/elso_spec/*, writes app/data/*.rds.
#
#   Rscript tools/build_elso_catalogue.R
#
# Inputs  (docs/elso_spec/):
#   elso_import.xsd     structure: element tree, order, cardinality, UniqueId length
#   elso_lookups.xlsx   one sheet per section: Field Name, Enum Data, soft/hard min/max
# Outputs (app/data/):
#   elso_catalogue.rds  list(tree, leaves, version)
#   elso_codelists.rds  named list of data.frame(code,label)
#
# NOTE: every XSD leaf is xsd:string — the schema only enforces element
# presence / nesting / order (+ UniqueId length). Code lists, date formats and
# numeric ranges are NOT in the XSD; they come from the lookups workbook and are
# enforced by the app's own validate.R, not by xml2::xml_validate.

suppressPackageStartupMessages({ library(xml2); library(readxl) })

`%||%`   <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a
# Run from the repo root:  Rscript tools/build_elso_catalogue.R
ROOT     <- getwd()
SPEC_DIR <- file.path(ROOT, "docs", "elso_spec")
OUT_DIR  <- file.path(ROOT, "app", "data")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

XSD_NS <- c(xsd = "http://www.w3.org/2001/XMLSchema")
SPEC_VERSION <- "01052026"

## ---- 1. parse the XSD element tree -----------------------------------------

# Collect the logical child <element> nodes of a complexType's compositor,
# descending through nested sequence/all/choice but STOPPING at each element
# (its own subtree is parsed separately). Preserves document order.
collect_child_elements <- function(node) {
  out <- list()
  for (ch in xml_children(node)) {
    nm <- xml_name(ch)
    if (nm == "element") out[[length(out) + 1L]] <- ch
    else if (nm %in% c("sequence", "all", "choice"))
      out <- c(out, collect_child_elements(ch))
  }
  out
}

parse_element <- function(el) {
  name   <- xml_attr(el, "name")
  minO   <- xml_attr(el, "minOccurs"); if (is.na(minO)) minO <- "1"
  maxO   <- xml_attr(el, "maxOccurs"); if (is.na(maxO)) maxO <- "1"
  type   <- xml_attr(el, "type")

  ct <- xml_find_first(el, "./xsd:complexType", XSD_NS)
  if (!is.na(ct)) {
    comp <- xml_find_first(ct, "./xsd:sequence|./xsd:all|./xsd:choice", XSD_NS)
    compositor <- if (!is.na(comp)) xml_name(comp) else NA_character_
    kids <- if (!is.na(comp)) collect_child_elements(comp) else list()
    children <- lapply(kids, parse_element)
    return(list(name = name, minOccurs = minO, maxOccurs = maxO,
                is_leaf = FALSE, compositor = compositor, children = children))
  }

  # leaf: type attr, or an inline simpleType/restriction
  base <- if (!is.na(type)) sub("^xsd:", "", type) else NA_character_
  minLen <- maxLen <- NA_character_
  st <- xml_find_first(el, "./xsd:simpleType/xsd:restriction", XSD_NS)
  if (!is.na(st)) {
    base   <- sub("^xsd:", "", xml_attr(st, "base") %||% base)
    ml <- xml_find_first(st, "./xsd:minLength", XSD_NS)
    xl <- xml_find_first(st, "./xsd:maxLength", XSD_NS)
    if (!is.na(ml)) minLen <- xml_attr(ml, "value")
    if (!is.na(xl)) maxLen <- xml_attr(xl, "value")
  }
  list(name = name, minOccurs = minO, maxOccurs = maxO, is_leaf = TRUE,
       base = base %||% "string", minLength = minLen, maxLength = maxLen,
       children = list())
}

xsd  <- read_xml(file.path(SPEC_DIR, "elso_import.xsd"))
root_el <- xml_find_first(xsd, "/xsd:schema/xsd:element[@name='PatientList']", XSD_NS)
tree <- parse_element(root_el)   # tree$name == "PatientList"

## ---- 2. flatten to a leaf/element table ------------------------------------

is_repeating <- function(maxO) identical(maxO, "unbounded") ||
  (!is.na(suppressWarnings(as.integer(maxO))) && as.integer(maxO) > 1L)

rows <- list()
walk <- function(node, path, repeat_level, section) {
  # path excludes the PatientList wrapper
  here <- if (identical(node$name, "PatientList")) character(0) else c(path, node$name)
  path_str <- paste(here, collapse = "/")
  rep_lvl  <- if (!identical(node$name, "PatientList") && is_repeating(node$maxOccurs))
                path_str else repeat_level
  # section = nearest named "container" for lookup matching (updated at complex nodes)
  sect <- section
  if (!node$is_leaf && !identical(node$name, "PatientList")) sect <- node$name

  if (node$is_leaf) {
    rows[[length(rows) + 1L]] <<- data.frame(
      path        = path_str,
      name        = node$name,
      parent      = paste(here[-length(here)], collapse = "/"),
      section     = section,
      repeat_level= rep_lvl,
      required    = as.integer(node$minOccurs) >= 1L,
      max_occurs  = node$maxOccurs,
      base        = node$base %||% "string",
      min_length  = node$minLength %||% NA_character_,
      max_length  = node$maxLength %||% NA_character_,
      stringsAsFactors = FALSE)
  } else {
    for (ch in node$children) walk(ch, here, rep_lvl, sect)
  }
}
walk(tree, character(0), "PatientXML", NA_character_)
leaves <- do.call(rbind, rows)

# infer a working "kind" for the app (all XSD types are string)
temporal <- grepl("Date|Time|DT$", leaves$name) | leaves$name %in%
  c("AdmitDate","DischargeDate","DeathDate","ArrestDateTime")
date_only <- leaves$name %in% c("Birthdate","ProcedureDate","ProcDate","LVDate")
leaves$kind <- ifelse(date_only, "date",
                ifelse(temporal, "datetime", "string"))

## ---- 3. code lists + ranges from the lookups workbook ----------------------

parse_enum <- function(s) {
  if (is.na(s) || !nzchar(trimws(s))) return(NULL)
  toks <- unlist(strsplit(s, "[,\r\n]+"))
  toks <- trimws(toks); toks <- toks[nzchar(toks)]
  code <- character(0); label <- character(0)
  for (t in toks) {
    kv <- trimws(unlist(strsplit(t, "=", fixed = TRUE)))
    if (length(kv) < 2) next
    lhs <- kv[1]; rhs <- kv[length(kv)]
    if (grepl("^[0-9]+$", rhs)) { code <- c(code, rhs); label <- c(label, lhs) }
    else if (grepl("^[0-9]+$", lhs)) { code <- c(code, lhs); label <- c(label, rhs) }
  }
  if (!length(code)) return(NULL)
  data.frame(code = code, label = label, stringsAsFactors = FALSE)
}

look_path <- file.path(SPEC_DIR, "elso_lookups.xlsx")
codelists <- list()          # key "<sheet>::<field>" -> df(code,label)
by_field  <- list()          # "<field>" -> df (last non-null wins; enums are field-specific)
ranges    <- list()          # "<sheet>::<field>" -> list(hard_min,hard_max,soft_min,soft_max)
for (sheet in excel_sheets(look_path)) {
  df <- tryCatch(as.data.frame(read_excel(look_path, sheet = sheet, col_types = "text")),
                 error = function(e) NULL)
  if (is.null(df) || !nrow(df)) next
  fn_col <- names(df)[grepl("field", tolower(names(df)))][1]
  en_col <- names(df)[grepl("enum",  tolower(names(df)))][1]
  hmin   <- names(df)[grepl("hard.*min", tolower(names(df)))][1]
  hmax   <- names(df)[grepl("hard.*max", tolower(names(df)))][1]
  smin   <- names(df)[grepl("soft.*min", tolower(names(df)))][1]
  smax   <- names(df)[grepl("soft.*max", tolower(names(df)))][1]
  if (is.na(fn_col)) next
  for (i in seq_len(nrow(df))) {
    field <- trimws(df[[fn_col]][i]); if (is.na(field) || !nzchar(field)) next
    key <- paste0(sheet, "::", field)
    if (!is.na(en_col)) {
      cl <- parse_enum(df[[en_col]][i])
      if (!is.null(cl)) { codelists[[key]] <- cl; by_field[[field]] <- cl }
    }
    ranges[[key]] <- list(
      hard_min = if (!is.na(hmin)) df[[hmin]][i] else NA,
      hard_max = if (!is.na(hmax)) df[[hmax]][i] else NA,
      soft_min = if (!is.na(smin)) df[[smin]][i] else NA,
      soft_max = if (!is.na(smax)) df[[smax]][i] else NA)
  }
}

## ---- 4. attach code lists to leaves (section match, then field fallback) ----

# Special-case: race enum is stored under field "PatientsRaces/Race".
if (!is.null(by_field[["PatientsRaces/Race"]]))
  by_field[["RaceCode"]] <- by_field[["PatientsRaces/Race"]]

leaves$codelist  <- NA_character_
leaves$has_codes <- FALSE
for (i in seq_len(nrow(leaves))) {
  nm <- leaves$name[i]; sect <- leaves$section[i]
  key <- NA_character_
  if (!is.na(sect)) {
    cand <- paste0(sect, "::", nm)
    if (!is.null(codelists[[cand]])) key <- cand
  }
  if (is.na(key) && !is.null(by_field[[nm]])) {
    codelists[[nm]] <- by_field[[nm]]; key <- nm
  }
  if (!is.na(key)) { leaves$codelist[i] <- key; leaves$has_codes[i] <- TRUE }
}
leaves$kind[leaves$has_codes & leaves$kind == "string"] <- "code"

## ---- 5. save ---------------------------------------------------------------

catalogue <- list(tree = tree, leaves = leaves, version = SPEC_VERSION,
                  built = as.character(Sys.time()))
saveRDS(catalogue, file.path(OUT_DIR, "elso_catalogue.rds"))
saveRDS(codelists, file.path(OUT_DIR, "elso_codelists.rds"))
saveRDS(ranges,    file.path(OUT_DIR, "elso_ranges.rds"))

cat(sprintf("Catalogue built (spec %s):\n", SPEC_VERSION))
cat(sprintf("  leaves:      %d\n", nrow(leaves)))
cat(sprintf("  required:    %d\n", sum(leaves$required)))
cat(sprintf("  coded:       %d leaves, %d code lists\n",
            sum(leaves$has_codes), length(codelists)))
cat(sprintf("  repeat levels: %s\n", paste(sort(unique(leaves$repeat_level)), collapse = ", ")))
cat("  sample required patient/run leaves:\n")
sel <- leaves[leaves$required & leaves$repeat_level %in% c("PatientXML"), c("path","kind")]
print(utils::head(sel, 12), row.names = FALSE)
