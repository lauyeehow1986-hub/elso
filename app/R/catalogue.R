# catalogue.R — load the bundled ELSO catalogue (built offline by
# tools/build_elso_catalogue.R from the official XSD + lookups workbook) and
# provide accessors used by the mapping UI, validator and generator.

el_data_dir <- function() {
  # resolve app/data whether sourced from app/ or the repo root
  cand <- c(file.path("app", "data"), "data",
            file.path(getOption("el.app_dir", "app"), "data"))
  hit <- cand[dir.exists(cand)][1]
  if (is.na(hit)) hit <- file.path("app", "data")
  hit
}

el_load_catalogue <- function(dir = el_data_dir()) {
  cat_path <- file.path(dir, "elso_catalogue.rds")
  cl_path  <- file.path(dir, "elso_codelists.rds")
  rg_path  <- file.path(dir, "elso_ranges.rds")
  if (!file.exists(cat_path))
    stop("ELSO catalogue not found at ", cat_path,
         " — run tools/build_elso_catalogue.R first.")
  list(catalogue = readRDS(cat_path),
       codelists = if (file.exists(cl_path)) readRDS(cl_path) else list(),
       ranges    = if (file.exists(rg_path)) readRDS(rg_path) else list())
}

# leaf table (data.frame) from a loaded catalogue
el_leaves <- function(cat) cat$catalogue$leaves

# the code-list data.frame(code,label) for a leaf row, or NULL
el_codelist <- function(cat, leaf_row) {
  key <- leaf_row$codelist
  if (is.na(key) || is.null(cat$codelists[[key]])) return(NULL)
  cat$codelists[[key]]
}

# human-friendly section label for grouping leaves in the UI
el_section_of <- function(path) {
  parts <- strsplit(path, "/", fixed = TRUE)[[1]]
  # drop the fixed spine tokens for a compact label
  spine <- c("PatientXML","HospitalizationList","HospitalizationXML",
             "RunList","RunXML")
  keep <- parts[!parts %in% spine]
  if (length(keep) <= 1) {
    # top-level scalar: label by its container level
    if (any(parts == "RunXML")) return("Run")
    if (any(parts == "HospitalizationXML")) return("Hospitalization")
    return("Patient")
  }
  paste(utils::head(keep, -1), collapse = " / ")
}

# ordered unique sections for UI grouping
el_sections <- function(cat) {
  lv <- el_leaves(cat)
  secs <- vapply(lv$path, el_section_of, character(1))
  unique(secs)
}

# the repeat-level "kind" for grouping bindings (patient/hospitalization/run/sub)
el_level_kind <- function(repeat_level) {
  if (repeat_level == "PatientXML") return("patient")
  if (grepl("/RunXML$", repeat_level)) return("run")
  if (grepl("/HospitalizationXML$", repeat_level)) return("hospitalization")
  if (repeat_level == "PatientXML/PatientsRaces/Race") return("race")
  "subcollection"
}
