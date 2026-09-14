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
#
# It also carries a NESTED Cardiac-addenda demo: a "cath" instrument (each row is
# one pre-ECLS CardiacCath, linked to a run via cc_run and keyed by cath_id) plus
# a "cath_dx" instrument (each row is one diagnostic finding, linked to its cath
# via dx_cath -> cath_id). This exercises a repeating list nested inside another
# repeating list. PT-0002 run 1 has TWO caths, and CATH-1A has TWO diagnostics.

set.seed(7)
outdir <- "samples"; dir.create(outdir, showWarnings = FALSE)

patients <- data.frame(
  patient_id       = c("ECMO-PT-0001", "ECMO-PT-0002", "ECMO-PT-0003"),
  sex              = c("1", "2", "1"),         # 1=Male 2=Female (labels match ELSO)
  dob              = c("15/06/1970", "02/11/1985", "23/03/2011"),
  race             = c("1", "4", "2"),         # 1=Asian 4=White 2=Black
  admit_dt         = c("31/01/2024 14:30:45", "05/02/2024 08:12:00", "18/03/2024 22:47:10"),
  discharge_dt     = c("12/03/2024 09:00:00", "20/02/2024 16:30:00", "25/03/2024 10:00:00"),
  discharged_alive = c("1", "1", "1"),         # 1=Yes alive (ELSO requires a discharge date + location)
  discharge_loc    = c("3", "3", "3"),         # DischargeLocation code
  stringsAsFactors = FALSE)

runs <- data.frame(
  patient_id   = c("ECMO-PT-0001", "ECMO-PT-0002", "ECMO-PT-0002", "ECMO-PT-0003"),
  run_no       = c("1", "1", "2", "1"),
  support_type = c("1", "1", "2", "3"),        # already ELSO SupportType codes
  ph_pre       = c("7.20", "7.35", "7.11", "7.44"),
  completed_by = c("YH", "YH", "YH", "team"),
  comp_enabled = c("1", "1", "0", "1"),        # ComplicationsEnabled (1 where a run has complications)
  inf_enabled  = c("0", "0", "0", "0"),        # InfectionsEnabled (no infections in this sample)
  # --- run-level minimum dataset ELSO's import validator requires (every run) ---
  adm_wt       = c("70", "80", "80", "40"),    # RunInfo AdmissionWeight (kg)
  adm_ht       = c("170","175","175","150"),   # RunInfo AdmissionHeight (cm)
  pre_ph       = c("7.20","7.35","7.11","7.44"), pre_hco3 = c("22","24","20","26"),
  pre_vent     = c("1","1","1","1"),           # VentilatorType code
  pre_sbp      = c("90","100","85","95"),  pre_dbp = c("55","60","50","58"),
  ecls_ph      = c("7.35","7.40","7.30","7.45"), ecls_hco3 = c("24","25","23","26"),
  ecls_vent    = c("1","1","1","1"),
  ecls_sbp     = c("100","105","95","100"), ecls_dbp = c("60","65","58","62"),
  mech_sc      = c("0","0","0","0"), renpul_sc = c("0","0","0","0"),  # 0 = none used (avoids a required support-code sub-list)
  meds_sc      = c("0","0","0","0"), vaso_sc   = c("0","0","0","0"),
  # Cardiac-addendum scalars — required by ELSO when a run carries a CardiacAddenda
  # block. Populated ONLY for the two cath-bearing runs (PT-0001 run1, PT-0002 run1);
  # blank on the others so their (optional) CardiacAddenda is omitted entirely.
  nyha         = c("1",  "1",  "", ""),
  scai_adm     = c("2",  "2",  "", ""),
  scai_pre     = c("3",  "3",  "", ""),
  ecls_cann    = c("4",  "4",  "", ""),
  vaso_score   = c("22", "18", "", ""),
  cann_loc     = c("5",  "5",  "", ""),
  icu_set      = c("12", "12", "", ""),        # IntensiveCareSetting (required when cann_loc = ICU)
  precip_event = c("6",  "6",  "", ""),
  precath      = c("1",  "1",  "", ""),
  duringcath   = c("0",  "0",  "", ""),
  aftercath    = c("0",  "0",  "", ""),
  vad_est      = c("1",  "1",  "", ""),         # VADEstimatedUnknown (flag; only 1 is valid)
  vad_date     = c("29/01/2024 08:00:00", "03/02/2024 08:00:00", "", ""),  # VADDateImplementation (before ECMO)
  vad_temp     = c("1",  "1",  "", ""),         # VADTempSupp
  # ECPR-2020 addendum scalars — populated ONLY for PT-0002 run 2 (a non-cardiac
  # run) so ecpr-including profiles differ; blank elsewhere -> that optional
  # ECPR2020Addenda block is omitted for the other runs.
  ecpr_precip    = c("", "", "6", ""),                    # ECPR PrecipitatingEvent
  ecpr_witnessed = c("", "", "1", ""),                    # WitnessedArrest (Yes)
  ecpr_arrest_dt = c("", "", "10/02/2024 07:00:00", ""),  # ArrestDateTime (before run-2 mode start)
  ecpr_cpr       = c("", "", "1", ""),                    # CPR performed
  ecpr_rhythm    = c("", "", "1", ""),                    # InitialPulselessRhythm
  # Trauma addendum scalars — populated ONLY for PT-0003 run 1.
  trauma_dt      = c("", "", "", "18/03/2024 20:00:00"),  # DateOfTrauma (before mode start)
  trauma_blunt   = c("", "", "", "1"),                    # MechanismBlunt
  trauma_pen     = c("", "", "", "0"),                    # MechanismPenetrating
  trauma_burns   = c("", "", "", "0"),                    # MechanismBurns
  stringsAsFactors = FALSE)

complications <- data.frame(
  patient_id = c("ECMO-PT-0001", "ECMO-PT-0002", "ECMO-PT-0003"),
  comp_run   = c("1", "1", "1"),
  comp_code  = c("541", "541", "541"),   # 541 is a point complication (uses ComplicationDate)
  comp_dt    = c("04/02/2024 09:16:00", "07/02/2024 03:00:00", "19/03/2024 06:00:00"),
  stringsAsFactors = FALSE)

# Cardiac contributing diagnoses (a list inside CardiacAddenda) — >=1 required when
# CardiacAddenda is present. Linked to the run via cdx_run.
cardiac_dx <- data.frame(
  patient_id = c("ECMO-PT-0001", "ECMO-PT-0002"),
  cdx_run    = c("1", "1"),
  cdx_code   = c("4", "4"),               # code 4 avoids graft-failure sub-requirements
  stringsAsFactors = FALSE)

diagnoses <- data.frame(
  patient_id = c("ECMO-PT-0001", "ECMO-PT-0002", "ECMO-PT-0002", "ECMO-PT-0003"),
  dx_run     = c("1", "1", "2", "1"),
  dx_code    = c("A00", "I47.2", "J80", "J80"),
  dx_primary = c("1", "1", "1", "1"),          # every run needs a primary diagnosis
  stringsAsFactors = FALSE)

# Cardiac addenda — pre-ECLS cardiac catheterisations (repeat inside a run).
# cc_run links a cath to its run (-> run_no); cath_id is the cath's own key that
# the nested diagnostics point back to. PT-0002 run 1 has two caths.
caths <- data.frame(
  patient_id  = c("ECMO-PT-0001", "ECMO-PT-0002", "ECMO-PT-0002"),
  cc_run      = c("1", "1", "1"),
  cath_id     = c("CATH-1A", "CATH-2A", "CATH-2B"),
  cath_option = c("1", "1", "1"),   # 1 = diagnostic-only cath (Diagnostics allowed, no Interventions required)
  cath_dt     = c("30/01/2024 10:00:00", "04/02/2024 08:00:00", "04/02/2024 09:00:00"),  # pre-ECLS: before mode start
  stringsAsFactors = FALSE)

# Nested diagnostics — each row is one finding inside a specific cath (list in a
# list). dx_cath links to cath_id. CATH-1A carries two diagnostics.
cath_dx <- data.frame(
  patient_id   = c("ECMO-PT-0001","ECMO-PT-0001","ECMO-PT-0002","ECMO-PT-0002","ECMO-PT-0002","ECMO-PT-0002"),
  dx_cath      = c("CATH-1A","CATH-1A","CATH-2A","CATH-2A","CATH-2B","CATH-2B"),
  cath_dx_code = c("3","5","3","5","3","5"),  # 3+5 together (5 = coronary dilation/stent needs its 3 sub-code)
  stringsAsFactors = FALSE)

# ---- run-level required collections (ELSO import mandates these per run) -----
# Modes: every run needs >=1 ECLS mode with a start, end and mode code.
modes <- data.frame(
  patient_id = c("ECMO-PT-0001", "ECMO-PT-0002", "ECMO-PT-0002", "ECMO-PT-0003"),
  mode_run   = c("1", "1", "2", "1"),
  mode_start = c("01/02/2024 06:00:00", "05/02/2024 12:00:00",
                 "10/02/2024 08:00:00", "19/03/2024 02:00:00"),
  mode_end   = c("06/02/2024 06:00:00", "09/02/2024 12:00:00",
                 "14/02/2024 08:00:00", "22/03/2024 02:00:00"),
  mode_ecls  = c("1", "1", "2", "1"),          # ELSO ECLSMode codes
  stringsAsFactors = FALSE)

# Equipment: pump / membrane lung / console, each with a device id + start/end.
pumps <- data.frame(
  patient_id = c("ECMO-PT-0001", "ECMO-PT-0002", "ECMO-PT-0002", "ECMO-PT-0003"),
  pump_run   = c("1", "1", "2", "1"),
  pump_devid = c("150", "150", "211", "150"),  # ELSO pump device codes
  pump_added = c("1", "1", "1", "1"),          # AddedReplaced (1=added)
  pump_start = c("01/02/2024 06:00:00", "05/02/2024 12:00:00",
                 "10/02/2024 08:00:00", "19/03/2024 02:00:00"),
  pump_end   = c("06/02/2024 06:00:00", "09/02/2024 12:00:00",
                 "14/02/2024 08:00:00", "22/03/2024 02:00:00"),
  stringsAsFactors = FALSE)
lungs <- data.frame(
  patient_id = c("ECMO-PT-0001", "ECMO-PT-0002", "ECMO-PT-0002", "ECMO-PT-0003"),
  lung_run   = c("1", "1", "2", "1"),
  lung_devid = c("220", "220", "220", "220"),  # ELSO membrane-lung device codes
  lung_added = c("1", "1", "1", "1"),
  lung_start = c("01/02/2024 06:00:00", "05/02/2024 12:00:00",
                 "10/02/2024 08:00:00", "19/03/2024 02:00:00"),
  lung_end   = c("06/02/2024 06:00:00", "09/02/2024 12:00:00",
                 "14/02/2024 08:00:00", "22/03/2024 02:00:00"),
  stringsAsFactors = FALSE)
consoles <- data.frame(
  patient_id  = c("ECMO-PT-0001", "ECMO-PT-0002", "ECMO-PT-0002", "ECMO-PT-0003"),
  console_run = c("1", "1", "2", "1"),
  console_devid = c("25", "25", "25", "25"),   # ELSO console device codes
  console_added = c("1", "1", "1", "1"),
  console_start = c("01/02/2024 06:00:00", "05/02/2024 12:00:00",
                    "10/02/2024 08:00:00", "19/03/2024 02:00:00"),
  console_end   = c("06/02/2024 06:00:00", "09/02/2024 12:00:00",
                    "14/02/2024 08:00:00", "22/03/2024 02:00:00"),
  stringsAsFactors = FALSE)

# Trauma addenda nested lists (attach to PT-0003 run 1 via *_run -> run_no).
# ECLSIndicationTrauma and TraumaRelatedInjury are run-level lists inside
# TraumaAddenda; one row each here.
trauma_ind <- data.frame(
  patient_id = "ECMO-PT-0003", tind_run = "1",
  tind_code  = "1",            # ECLSIndicationTrauma/CodeId
  stringsAsFactors = FALSE)
trauma_inj <- data.frame(
  patient_id = "ECMO-PT-0003", tinj_run = "1",
  tinj_code  = "1",            # TraumaRelatedInjury/CodeId
  stringsAsFactors = FALSE)

## ---- data dictionary + choices ---------------------------------------------
codelists <- list(
  sex   = c("0"="Unknown","1"="Male","2"="Female"),
  race  = c("0"="Unknown","1"="Asian","2"="Black","3"="Hispanic","4"="White"),
  yesno = c("0"="No","1"="Yes","2"="On ECMO"))

dd <- data.frame(
  variable = c("patient_id","sex","dob","race","admit_dt","discharge_dt","discharged_alive",
               "run_no","support_type","ph_pre","completed_by",
               "comp_run","comp_code","comp_dt","dx_run","dx_code","dx_primary",
               "cc_run","cath_id","cath_option","cath_dt","dx_cath","cath_dx_code",
               "mode_run","mode_start","mode_end","mode_ecls",
               "pump_run","pump_devid","pump_start","pump_end",
               "lung_run","lung_devid","lung_start","lung_end",
               "console_run","console_devid","console_start","console_end"),
  form_name= c(rep("demographics",7), rep("run",4), rep("complication",3), rep("diagnosis",3),
               rep("cath",4), rep("cath_dx",2),
               rep("mode",4), rep("pumps",4), rep("lungs",4), rep("consoles",4)),
  label    = c("Patient ID","Sex","Date of birth","Race","Admission date/time",
               "Discharge date/time","Discharged alive","Run number","Support type",
               "Pre-ECLS pH","Completed by","Complication run","Complication code",
               "Complication date/time","Diagnosis run","Diagnosis code","Primary diagnosis",
               "Cath run","Cath ID","Cath option","Cath date/time",
               "Cath (for diagnostic)","Cath diagnostic code",
               "Mode run","Mode start","Mode end","ECLS mode",
               "Pump run","Pump device id","Pump start","Pump end",
               "Lung run","Lung device id","Lung start","Lung end",
               "Console run","Console device id","Console start","Console end"),
  type     = c("text","radio","text","radio","datetime_seconds_dmy","datetime_seconds_dmy","radio",
               "text","text","text","text","text","text","datetime_seconds_dmy","text","text","radio",
               "text","text","text","datetime_seconds_dmy","text","text",
               "text","datetime_seconds_dmy","datetime_seconds_dmy","text",
               "text","text","datetime_seconds_dmy","datetime_seconds_dmy",
               "text","text","datetime_seconds_dmy","datetime_seconds_dmy",
               "text","text","datetime_seconds_dmy","datetime_seconds_dmy"),
  choices  = c("", "0, Unknown | 1, Male | 2, Female", "",
               "0, Unknown | 1, Asian | 2, Black | 3, Hispanic | 4, White", "", "",
               "0, No | 1, Yes | 2, On ECMO", "","","","","","","","","",
               "0, No | 1, Yes", "","","","","","",
               "","","","",  "","","","",  "","","","",  "","","",""),
  stringsAsFactors = FALSE)
dd <- rbind(dd, data.frame(
  variable = c("comp_enabled","inf_enabled","pump_added","lung_added","console_added"),
  form_name= c("run","run","pumps","lungs","consoles"),
  label    = c("Complications enabled","Infections enabled",
               "Pump added/replaced","Lung added/replaced","Console added/replaced"),
  type     = c("text","text","text","text","text"),
  choices  = c("","","","",""),
  stringsAsFactors = FALSE))
dd <- rbind(dd, data.frame(
  variable = c("nyha","scai_adm","scai_pre","ecls_cann","vaso_score","cann_loc",
               "precip_event","precath","duringcath","aftercath","cdx_run","cdx_code"),
  form_name= c(rep("run",10), "cardiac_dx","cardiac_dx"),
  label    = c("NYHA category","SCAI at admission","SCAI pre-ECMO","ECLS cannulation",
               "Vasoactive inotrope score","Cannulation location","Precipitating event",
               "Pre-cath yes/no","During-cath yes/no","After-cath yes/no",
               "Cardiac dx run","Cardiac contributing diagnosis code"),
  type     = c(rep("text",12)),
  choices  = c(rep("",12)),
  stringsAsFactors = FALSE))
dd <- rbind(dd, data.frame(
  variable = c("discharge_loc",
               "adm_wt","adm_ht","pre_ph","pre_hco3","pre_vent","pre_sbp","pre_dbp",
               "ecls_ph","ecls_hco3","ecls_vent","ecls_sbp","ecls_dbp",
               "mech_sc","renpul_sc","meds_sc","vaso_sc",
               "icu_set","vad_est","vad_date","vad_temp"),
  form_name= c("demographics", rep("run",20)),
  label    = c("Discharge location",
               "Admission weight","Admission height","Pre pH","Pre HCO3","Pre vent type",
               "Pre SBP","Pre DBP","ECLS pH","ECLS HCO3","ECLS vent type","ECLS SBP","ECLS DBP",
               "Mechanical support used","Renal/pulm/other support used","Medications support used",
               "Vasoactive support used","Intensive care setting","VAD estimated unknown",
               "VAD date of implantation","VAD temporary support"),
  type     = c(rep("text",19), "datetime_seconds_dmy", "text"),
  choices  = c(rep("",21)),
  stringsAsFactors = FALSE))
dd <- rbind(dd, data.frame(
  variable = c("ecpr_precip","ecpr_witnessed","ecpr_arrest_dt","ecpr_cpr","ecpr_rhythm",
               "trauma_dt","trauma_blunt","trauma_pen","trauma_burns",
               "tind_run","tind_code","tinj_run","tinj_code"),
  form_name= c(rep("run",9), "trauma_ind","trauma_ind","trauma_inj","trauma_inj"),
  label    = c("ECPR precipitating event","ECPR witnessed arrest","ECPR arrest date/time",
               "ECPR CPR performed","ECPR initial pulseless rhythm",
               "Date of trauma","Mechanism blunt","Mechanism penetrating","Mechanism burns",
               "Trauma indication run","ECLS indication (trauma) code",
               "Trauma injury run","Trauma related injury code"),
  type     = c("text","text","datetime_seconds_dmy","text","text",
               "datetime_seconds_dmy","text","text","text",
               "text","text","text","text"),
  choices  = c(rep("",13)),
  stringsAsFactors = FALSE))
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
              bind_form(diagnoses, "diagnosis"),
              bind_form(caths, "cath"),
              bind_form(cath_dx, "cath_dx"),
              bind_form(modes, "mode"),
              bind_form(pumps, "pumps"),
              bind_form(lungs, "lungs"),
              bind_form(consoles, "consoles"),
              bind_form(cardiac_dx, "cardiac_dx"),
              bind_form(trauma_ind, "trauma_ind"),
              bind_form(trauma_inj, "trauma_inj"))
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
forms <- c("demographics","run","complication","diagnosis","cath","cath_dx",
           "mode","pumps","lungs","consoles","cardiac_dx","trauma_ind","trauma_inj")
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
  hh <- which(caths$patient_id == pid)
  for (k in seq_along(hh)) blocks <- paste0(blocks, form_block(caths, hh[k], "cath", k))
  xx <- which(cath_dx$patient_id == pid)
  for (k in seq_along(xx)) blocks <- paste0(blocks, form_block(cath_dx, xx[k], "cath_dx", k))
  mm <- which(modes$patient_id == pid)
  for (k in seq_along(mm)) blocks <- paste0(blocks, form_block(modes, mm[k], "mode", k))
  pp <- which(pumps$patient_id == pid)
  for (k in seq_along(pp)) blocks <- paste0(blocks, form_block(pumps, pp[k], "pumps", k))
  ll <- which(lungs$patient_id == pid)
  for (k in seq_along(ll)) blocks <- paste0(blocks, form_block(lungs, ll[k], "lungs", k))
  nn <- which(consoles$patient_id == pid)
  for (k in seq_along(nn)) blocks <- paste0(blocks, form_block(consoles, nn[k], "consoles", k))
  cd <- which(cardiac_dx$patient_id == pid)
  for (k in seq_along(cd)) blocks <- paste0(blocks, form_block(cardiac_dx, cd[k], "cardiac_dx", k))
  ti <- which(trauma_ind$patient_id == pid)
  for (k in seq_along(ti)) blocks <- paste0(blocks, form_block(trauma_ind, ti[k], "trauma_ind", k))
  tj <- which(trauma_inj$patient_id == pid)
  for (k in seq_along(tj)) blocks <- paste0(blocks, form_block(trauma_inj, tj[k], "trauma_inj", k))
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
cat("Cardiac addenda: caths link to runs via cc_run; nested cath_dx link via",
    "dx_cath -> cath_id (PT-0002 run 1 has 2 caths; CATH-1A has 2 diagnostics).\n")
cat("ECPR-2020 addenda: run-level scalars on PT-0002 run 2.",
    "Trauma addenda: run-level scalars on PT-0003 run 1 + nested ECLSIndicationTrauma",
    "(trauma_ind) and TraumaRelatedInjury (trauma_inj).\n")
