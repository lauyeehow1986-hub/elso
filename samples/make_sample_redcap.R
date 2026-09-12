# make_sample_redcap.R — generate a SYNTHETIC REDCap ECMO export for testing.
# NO real patient data. Writes to samples/:
#   sample_redcap.odm.xml         REDCap CDISC ODM (metadata + clinical data)
#   sample_redcap_records.csv     flat records export
#   sample_redcap_dictionary.csv  data dictionary
#
#   Rscript samples/make_sample_redcap.R
#
# Shape: a non-repeating "demographics" instrument (patient-level) + repeating
# "run", "complication", "diagnosis" instruments. Patient 2 has TWO runs, and
# complications/diagnoses link to a run via *_run. Dates are dd/mm/yyyy hh:mm:ss
# (a common REDCap format that is NOT ELSO's) to exercise date conversion.

set.seed(7)
outdir <- "samples"; dir.create(outdir, showWarnings = FALSE)

patients <- data.frame(
  patient_id       = c("ECMO-PT-0001", "ECMO-PT-0002", "ECMO-PT-0003"),
  sex              = c("1", "2", "1"),         # 1=Male 2=Female (labels match ELSO)
  dob              = c("15/06/1970", "02/11/1985", "23/03/2011"),
  race             = c("1", "4", "2"),         # 1=Asian 4=White 2=Black
  admit_dt         = c("31/01/2024 14:30:45", "05/02/2024 08:12:00", "18/03/2024 22:47:10"),
  discharge_dt     = c("12/03/2024 09:00:00", "20/02/2024 16:30:00", ""),
  discharged_alive = c("1", "1", "2"),         # 0=No 1=Yes 2=On ECMO
  stringsAsFactors = FALSE)

runs <- data.frame(
  patient_id   = c("ECMO-PT-0001", "ECMO-PT-0002", "ECMO-PT-0002", "ECMO-PT-0003"),
  run_no       = c("1", "1", "2", "1"),
  support_type = c("1", "1", "2", "3"),        # already ELSO SupportType codes
  ph_pre       = c("7.20", "7.35", "7.11", "7.44"),
  completed_by = c("YH", "YH", "YH", "team"),
  stringsAsFactors = FALSE)

complications <- data.frame(
  patient_id = c("ECMO-PT-0001", "ECMO-PT-0002", "ECMO-PT-0003"),
  comp_run   = c("1", "1", "1"),
  comp_code  = c("541", "201", "541"),
  comp_dt    = c("04/02/2024 09:16:00", "07/02/2024 03:00:00", "19/03/2024 06:00:00"),
  stringsAsFactors = FALSE)

diagnoses <- data.frame(
  patient_id = c("ECMO-PT-0001", "ECMO-PT-0002", "ECMO-PT-0002"),
  dx_run     = c("1", "1", "2"),
  dx_code    = c("A00", "I47.2", "J80"),
  dx_primary = c("1", "1", "0"),
  stringsAsFactors = FALSE)

## ---- data dictionary + choices ---------------------------------------------
codelists <- list(
  sex   = c("0"="Unknown","1"="Male","2"="Female"),
  race  = c("0"="Unknown","1"="Asian","2"="Black","3"="Hispanic","4"="White"),
  yesno = c("0"="No","1"="Yes","2"="On ECMO"))

dd <- data.frame(
  variable = c("patient_id","sex","dob","race","admit_dt","discharge_dt","discharged_alive",
               "run_no","support_type","ph_pre","completed_by",
               "comp_run","comp_code","comp_dt","dx_run","dx_code","dx_primary"),
  form_name= c(rep("demographics",7), rep("run",4), rep("complication",3), rep("diagnosis",3)),
  label    = c("Patient ID","Sex","Date of birth","Race","Admission date/time",
               "Discharge date/time","Discharged alive","Run number","Support type",
               "Pre-ECLS pH","Completed by","Complication run","Complication code",
               "Complication date/time","Diagnosis run","Diagnosis code","Primary diagnosis"),
  type     = c("text","radio","text","radio","datetime_seconds_dmy","datetime_seconds_dmy","radio",
               "text","text","text","text","text","text","datetime_seconds_dmy","text","text","radio"),
  choices  = c("", "0, Unknown | 1, Male | 2, Female", "",
               "0, Unknown | 1, Asian | 2, Black | 3, Hispanic | 4, White", "", "",
               "0, No | 1, Yes | 2, On ECMO", "","","","","","","","","",
               "0, No | 1, Yes"),
  stringsAsFactors = FALSE)
write.csv(dd, file.path(outdir, "sample_redcap_dictionary.csv"), row.names = FALSE)

## ---- flat records CSV (REDCap-style long export) ---------------------------
mk <- function(df, form) {
  df$redcap_repeat_instrument <- if (form == "demographics") "" else form
  df$redcap_repeat_instance   <- if (form == "demographics") "" else
    ave(seq_len(nrow(df)), df$patient_id, FUN = seq_along)
  names(df)[names(df) == "patient_id"] <- "record_id"
  df
}
flat_cols <- unique(c("record_id","redcap_repeat_instrument","redcap_repeat_instance",
                      dd$variable[dd$variable != "patient_id"]))
bind_form <- function(df, form) {
  d <- mk(df, form)
  for (c in setdiff(flat_cols, names(d))) d[[c]] <- ""
  d[, flat_cols]
}
flat <- rbind(bind_form(patients, "demographics"),
              bind_form(runs, "run"),
              bind_form(complications, "complication"),
              bind_form(diagnoses, "diagnosis"))
write.csv(flat, file.path(outdir, "sample_redcap_records.csv"), row.names = FALSE)

## ---- REDCap ODM XML --------------------------------------------------------
esc <- function(x) { x <- as.character(x)
  x <- gsub("&","&amp;",x); x <- gsub("<","&lt;",x); gsub(">","&gt;",x) }

item_defs <- character(0); cl_defs <- character(0)
for (i in seq_len(nrow(dd))) {
  clref <- ""
  if (nzchar(dd$choices[i])) clref <- sprintf('<CodeListRef CodeListOID="cl_%s"/>', dd$variable[i])
  item_defs <- c(item_defs, sprintf(
    '<ItemDef OID="%s" Name="%s" DataType="text"><Question><TranslatedText>%s</TranslatedText></Question>%s</ItemDef>',
    dd$variable[i], esc(dd$variable[i]), esc(dd$label[i]), clref))
}
choice_map <- list(sex="sex", race="race", discharged_alive="yesno", dx_primary="yesno")
for (v in names(choice_map)) {
  cl <- codelists[[choice_map[[v]]]]
  items <- paste0(sprintf('<CodeListItem CodedValue="%s"><Decode><TranslatedText>%s</TranslatedText></Decode></CodeListItem>',
                          names(cl), esc(unname(cl))), collapse = "")
  cl_defs <- c(cl_defs, sprintf('<CodeList OID="cl_%s" Name="%s" DataType="text">%s</CodeList>', v, v, items))
}
forms <- c("demographics","run","complication","diagnosis")
form_defs <- character(0); ig_defs <- character(0)
for (f in forms) {
  vars <- dd$variable[dd$form_name == f]
  form_defs <- c(form_defs, sprintf('<FormDef OID="Form.%s" Name="%s" Repeating="%s"><ItemGroupRef ItemGroupOID="ig.%s"/></FormDef>',
                                    f, f, if (f=="demographics") "No" else "Yes", f))
  ig_defs <- c(ig_defs, sprintf('<ItemGroupDef OID="ig.%s" Name="%s" Repeating="No">%s</ItemGroupDef>',
                                f, f, paste0(sprintf('<ItemRef ItemOID="%s"/>', vars), collapse="")))
}

item_data <- function(df, i, vars) paste0(
  vapply(vars, function(v) if (nzchar(df[[v]][i])) sprintf('<ItemData ItemOID="%s" Value="%s"/>', v, esc(df[[v]][i])) else "",
         character(1)), collapse = "")
form_block <- function(df, i, f, repeatkey = NULL) {
  vars <- intersect(dd$variable[dd$form_name == f], names(df))  # incl. patient_id (=record_id)
  rk <- if (!is.null(repeatkey)) sprintf(' FormRepeatKey="%s"', repeatkey) else ""
  sprintf('<FormData FormOID="Form.%s"%s><ItemGroupData ItemGroupOID="ig.%s">%s</ItemGroupData></FormData>',
          f, rk, f, item_data(df, i, vars))
}

subj_blocks <- character(0)
for (pid in patients$patient_id) {
  pi <- which(patients$patient_id == pid)
  blocks <- form_block(patients, pi, "demographics")
  rr <- which(runs$patient_id == pid)
  for (k in seq_along(rr)) blocks <- paste0(blocks, form_block(runs, rr[k], "run", k))
  cc <- which(complications$patient_id == pid)
  for (k in seq_along(cc)) blocks <- paste0(blocks, form_block(complications, cc[k], "complication", k))
  gg <- which(diagnoses$patient_id == pid)
  for (k in seq_along(gg)) blocks <- paste0(blocks, form_block(diagnoses, gg[k], "diagnosis", k))
  subj_blocks <- c(subj_blocks, sprintf(
    '<SubjectData SubjectKey="%s"><StudyEventData StudyEventOID="ev.baseline">%s</StudyEventData></SubjectData>',
    pid, blocks))
}

odm <- paste0(
  '<?xml version="1.0" encoding="UTF-8"?>\n',
  '<ODM xmlns="http://www.cdisc.org/ns/odm/v1.3" xmlns:redcap="https://projectredcap.org" FileType="Snapshot" FileOID="elso-sample">\n',
  '<Study OID="ecmo"><MetaDataVersion OID="md1" Name="ECMO">',
  paste0(item_defs, collapse=""), paste0(cl_defs, collapse=""),
  paste0(form_defs, collapse=""), paste0(ig_defs, collapse=""),
  '</MetaDataVersion></Study>\n',
  '<ClinicalData StudyOID="ecmo" MetaDataVersionOID="md1">',
  paste0(subj_blocks, collapse=""), '</ClinicalData>\n</ODM>\n')

writeLines(odm, file.path(outdir, "sample_redcap.odm.xml"))
cat("Wrote samples/sample_redcap.odm.xml,",
    "sample_redcap_records.csv, sample_redcap_dictionary.csv\n")
cat("Patients: 3 (PT-0002 has 2 runs); complications & diagnoses link via *_run.\n")
