# Headless unit checks for the addenda-profile pruner.
# Run from the repo root:
#   "C:/Program Files/R/R-4.5.2/bin/Rscript.exe" tests/test_addenda_profile.R
suppressWarnings(source("app/global.R"))
CAT <- el_load_catalogue()

# A tiny synthetic doc containing all three addenda under one RunXML.
doc_xml <- paste0(
  '<PatientList xmlns="urn:run-schema"><PatientXML><HospitalizationList>',
  '<HospitalizationXML><RunList><RunXML>',
  '<RunNo>1</RunNo>',
  '<CardiacAddenda><NYHACategory>2</NYHACategory></CardiacAddenda>',
  '<ECPR2020Addenda><WitnessedArrest>1</WitnessedArrest></ECPR2020Addenda>',
  '<TraumaAddenda><MechanismBlunt>1</MechanismBlunt></TraumaAddenda>',
  '</RunXML></RunList></HospitalizationXML></HospitalizationList></PatientXML></PatientList>')
mk <- function() xml2::read_xml(doc_xml)
present <- function(doc, ln)
  length(xml2::xml_find_all(doc, sprintf("//*[local-name()='%s']", ln))) > 0

# tokens map
stopifnot(identical(el_addenda_tokens(),
  c(cardiac="CardiacAddenda", ecpr="ECPR2020Addenda", trauma="TraumaAddenda")))

# 8 combinations, stable order, right tokens
combos <- el_addenda_combinations()
stopifnot(length(combos) == 8L)
stopifnot(identical(vapply(combos, `[[`, "", "token"),
  c("main","cardiac","ecpr","trauma","cardiac_ecpr","cardiac_trauma",
    "ecpr_trauma","cardiac_ecpr_trauma")))
stopifnot(identical(combos[[1]]$include, character(0)))
stopifnot(setequal(combos[[8]]$include, c("cardiac","ecpr","trauma")))

# main-only: no addenda remain
d <- el_apply_addenda_profile(mk(), character(0))
stopifnot(!present(d,"CardiacAddenda"), !present(d,"ECPR2020Addenda"),
          !present(d,"TraumaAddenda"))

# cardiac-only: keep cardiac, drop the other two
d <- el_apply_addenda_profile(mk(), "cardiac")
stopifnot(present(d,"CardiacAddenda"), !present(d,"ECPR2020Addenda"),
          !present(d,"TraumaAddenda"))

# ecpr+trauma: drop cardiac only
d <- el_apply_addenda_profile(mk(), c("ecpr","trauma"))
stopifnot(!present(d,"CardiacAddenda"), present(d,"ECPR2020Addenda"),
          present(d,"TraumaAddenda"))

# all three: keep everything
d <- el_apply_addenda_profile(mk(), c("cardiac","ecpr","trauma"))
stopifnot(present(d,"CardiacAddenda"), present(d,"ECPR2020Addenda"),
          present(d,"TraumaAddenda"))

# idempotent / absent addendum is a no-op (prune twice)
d <- el_apply_addenda_profile(el_apply_addenda_profile(mk(),"cardiac"),"cardiac")
stopifnot(present(d,"CardiacAddenda"))

# batch driver: writes 8 files + returns a results data.frame
tmp <- file.path(tempdir(), paste0("elso_combo_", as.integer(runif(1,1,1e6))))
dir.create(tmp, recursive = TRUE, showWarnings = FALSE)
# minimal hierarchy: one patient/hosp/run with UniqueId only (>=10 chars)
hier <- list(list(
  row = c(UniqueId = "TESTPT0001"),
  races = list(), hosps = list(list(
    row = setNames(character(0), character(0)),
    runs = list(list(row = c(RunNo = "1"), coll = list()))))))
res <- el_generate_all_combinations(
  CAT, hier, map = list(UniqueId = list(source = "UniqueId")),
  recode = list(), datefmt = list(), out_dir = tmp,
  xsd_path = getOption("el.xsd_path"))
stopifnot(is.data.frame(res), nrow(res) == 8L)
stopifnot(all(c("profile","token","xsd_valid","n_error","file") %in% names(res)))
files <- list.files(tmp, pattern = "\\.xml$")
stopifnot(length(files) == 8L)
stopifnot("elso_import__main.xml" %in% files)
stopifnot("elso_import__cardiac_ecpr_trauma.xml" %in% files)
cat("test batch: PASS\n")

cat("test_addenda_profile: PASS\n")
