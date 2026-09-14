# End-to-end: the bundled sample + sample_mapping.json -> all 8 addenda
# combinations build XSD-valid with 0 semantic errors, and each file retains
# exactly the addenda its profile selects.
# Run from the repo root:
#   "C:/Program Files/R/R-4.5.2/bin/Rscript.exe" tests/test_all_combinations.R
suppressWarnings(source("app/global.R"))
CAT <- el_load_catalogue()

parsed <- el_read_redcap_odm("samples/sample_redcap.odm.xml")
tmpl   <- el_load_mapping("samples/sample_mapping.json")
hier   <- el_build_hierarchy(parsed, tmpl$binding)

tmp <- file.path(tempdir(), "combo_e2e"); unlink(tmp, recursive = TRUE)
res <- el_generate_all_combinations(CAT, hier, tmpl$map, tmpl$recode, tmpl$datefmt,
                                    out_dir = tmp, xsd_path = getOption("el.xsd_path"))
print(res)
stopifnot(nrow(res) == 8L)
stopifnot(all(res$xsd_valid))          # every combination XSD-valid
stopifnot(all(res$n_error == 0L))      # every combination 0 semantic errors

# addenda presence per profile file
has <- function(f, ln) length(xml2::xml_find_all(
  xml2::read_xml(file.path(tmp, f)), sprintf("//*[local-name()='%s']", ln))) > 0
C <- "CardiacAddenda"; E <- "ECPR2020Addenda"; T <- "TraumaAddenda"

stopifnot(!has("elso_import__main.xml", C), !has("elso_import__main.xml", E),
          !has("elso_import__main.xml", T))
stopifnot( has("elso_import__cardiac.xml", C), !has("elso_import__cardiac.xml", E),
          !has("elso_import__cardiac.xml", T))
stopifnot(!has("elso_import__ecpr.xml", C),  has("elso_import__ecpr.xml", E),
          !has("elso_import__ecpr.xml", T))
stopifnot(!has("elso_import__trauma.xml", C), !has("elso_import__trauma.xml", E),
           has("elso_import__trauma.xml", T))
stopifnot( has("elso_import__cardiac_ecpr.xml", C),  has("elso_import__cardiac_ecpr.xml", E),
          !has("elso_import__cardiac_ecpr.xml", T))
stopifnot(!has("elso_import__ecpr_trauma.xml", C),  has("elso_import__ecpr_trauma.xml", E),
           has("elso_import__ecpr_trauma.xml", T))
stopifnot( has("elso_import__cardiac_ecpr_trauma.xml", C),
           has("elso_import__cardiac_ecpr_trauma.xml", E),
           has("elso_import__cardiac_ecpr_trauma.xml", T))
cat("test_all_combinations: PASS\n")
