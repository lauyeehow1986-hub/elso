# project.R — portable project folder + SHA-256 manifest + simple JSONL log.
# Everything for a conversion job lives in one self-contained folder so it can be
# moved between machines.
#
#   <project>/
#     project.json     name, center config, created/updated
#     inputs/          registered REDCap exports
#     outputs/         generated ELSO XML + manifest + validation report
#     mappings/        saved mapping templates (JSON)
#     log.jsonl        append-only action log

suppressPackageStartupMessages(library(jsonlite))

el_project_paths <- function(dir) list(
  dir      = dir,
  config   = file.path(dir, "project.json"),
  inputs   = file.path(dir, "inputs"),
  outputs  = file.path(dir, "outputs"),
  mappings = file.path(dir, "mappings"),
  log      = file.path(dir, "log.jsonl"))

el_project_create <- function(dir, name = basename(dir), center_no = "") {
  p <- el_project_paths(dir)
  for (d in c(dir, p$inputs, p$outputs, p$mappings))
    dir.create(d, showWarnings = FALSE, recursive = TRUE)
  cfg <- list(name = name, center_no = center_no,
              created = as.character(Sys.time()),
              updated = as.character(Sys.time()))
  jsonlite::write_json(cfg, p$config, auto_unbox = TRUE, pretty = TRUE)
  el_log_append(dir, "project_create", list(name = name))
  cfg
}

el_project_open <- function(dir) {
  p <- el_project_paths(dir)
  if (!file.exists(p$config)) stop("Not an ELSO project: ", dir)
  jsonlite::fromJSON(p$config)
}

el_project_save <- function(dir, cfg) {
  cfg$updated <- as.character(Sys.time())
  jsonlite::write_json(cfg, el_project_paths(dir)$config,
                       auto_unbox = TRUE, pretty = TRUE)
  cfg
}

el_sha256_file <- function(path) {
  if (!file.exists(path)) return(NA_character_)
  as.character(openssl::sha256(file(path)))
}

el_manifest_write <- function(dir) {
  files <- list.files(dir, recursive = TRUE, full.names = TRUE)
  files <- files[basename(files) != "manifest.json"]
  entries <- lapply(files, function(f) list(
    file = sub(paste0("^", gsub("([.\\\\+*?\\[^\\]$(){}=!<>|:#-])", "\\\\\\1", dir), "/?"), "", f),
    sha256 = el_sha256_file(f),
    bytes = file.info(f)$size))
  mp <- file.path(dir, "outputs", "manifest.json")
  jsonlite::write_json(list(generated = as.character(Sys.time()), entries = entries),
                       mp, auto_unbox = TRUE, pretty = TRUE)
  mp
}

el_log_append <- function(dir, action, detail = list()) {
  line <- jsonlite::toJSON(list(
    time = as.character(Sys.time()), action = action, detail = detail),
    auto_unbox = TRUE)
  cat(line, "\n", file = el_project_paths(dir)$log, append = TRUE, sep = "")
  invisible(TRUE)
}
