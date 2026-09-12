# global.R — load the ELSO converter core in dependency order. Sourced by app.R
# and by the headless tests. Pure-R; no network.

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(DT)
})

el_source_dir <- function(dir) {
  files <- c("util.R", "catalogue.R", "redcap.R", "grouping.R",
             "mapping.R", "generate.R", "validate.R", "deident.R", "project.R")
  for (f in files) {
    fp <- file.path(dir, f)
    if (file.exists(fp)) sys.source(fp, envir = globalenv())
  }
}

.el_app_dir <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) "app")
if (is.null(.el_app_dir) || !nzchar(.el_app_dir) || !dir.exists(.el_app_dir))
  .el_app_dir <- if (dir.exists("app")) "app" else "."
options(el.app_dir = normalizePath(.el_app_dir, mustWork = FALSE))
el_source_dir(file.path(.el_app_dir, "R"))

# bundled schema for XSD validation at runtime
options(el.xsd_path = normalizePath(file.path(.el_app_dir, "data", "elso_import.xsd"),
                                    mustWork = FALSE))
