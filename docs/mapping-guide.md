# Mapping guide — REDCap → ELSO

This walks through converting a REDCap export to ELSO import XML, using the bundled
synthetic sample as the worked example.

## 1. Understand the two shapes
- **REDCap** is flat/long: one row per (record, event, instrument, instance). A patient
  with two ECMO runs has multiple rows.
- **ELSO** is nested: `PatientXML → HospitalizationList/HospitalizationXML →
  RunList/RunXML`, with run-level repeating collections and optional addenda. The patient
  key is `UniqueId` (10–20 chars); runs are keyed by `RunNo`.

## 2. Grouping keys (Map tab → "Grouping keys")
Tell the app how rows collapse into the hierarchy:
- **Patient key** — the column identifying a patient. For ODM this is `.subject`
  (the ODM `SubjectKey`); for CSV it is `record_id`.
- **Patient/hosp instrument** — the non-repeating form that carries patient +
  hospitalization scalar fields (e.g. `demographics`).
- **Run instrument** — the repeating form where each row is one ECMO run (e.g. `run`).
  One `RunXML` is produced per row of this instrument, per patient.
- **Run key field** — the field whose value is `RunNo` and links sub-collections to a run
  (e.g. `run_no`).

If no run instrument is chosen, the app produces one run per patient from the patient row.

## 3. Sub-collection bindings (run-level + addenda repeats)
Every ELSO repeating list can be bound to a REDCap repeating instrument. The binders are
grouped into collapsible blocks: **Run-level collections** (Diagnoses, Complications,
Infections, Procedures, Modes, Cannulations, Equipment, …) and the three addenda blocks
**Cardiac addenda**, **ECPR 2020 addenda**, **Trauma addenda**. Open an addenda block only
if you are submitting that addendum — leave it untouched to omit it.

Each binder has:
- **REDCap instrument** — the form supplying the rows (e.g. `diagnosis`).
- **Link field** — the field in that instrument matching its parent's key, so each row
  lands under the right parent (e.g. `dx_run` → `run_no`). If left blank, rows attach to
  the first parent instance only.

**Nesting.** Some addenda lists live inside another list — e.g. a cardiac
catheterisation's *Diagnostics* and *Interventions* belong to each *CardiacCath*, and
*CannulationPurposes* belong to each *Cannulation*. These binders are marked **nested** and
their *Link field* matches the **parent list's key**, not the run key. A list that can hold
nested children (e.g. `CardiacCath`, `Cannulation`) also shows a **Key field (for nested
lists)** — the field whose value identifies that row, which the nested list links back to.

Example nesting: bind `CardiacCath` (instrument `cath`, link `cc_run` → `run_no`, key
`cath_id`), then bind its nested `Diagnostic` (instrument `cath_dx`, link `dx_cath` →
`cath_id`). Each catheterisation then carries its own diagnostics.

## 4. Field mapping (Map tab → "Field mapping")
- Click **Auto-suggest mapping** to match REDCap fields to ELSO leaves by name, synonym,
  and label.
- Pick a **Section** and adjust individual leaves. Badges: ★ required, `[coded]`,
  `[date]`.
- Click **Apply this section** to save your edits for that section.
- **Save template** downloads a JSON bundle (grouping + map + recodes + date formats).
  **Load template** reapplies it to a new export with the same structure.

## 5. Recode values (Recode tab)
Coded ELSO fields need ELSO numeric codes. Where a REDCap choice label matches an ELSO
code-list label (e.g. `Male`), the crosswalk is filled automatically (REDCap value →
ELSO code). Review the table before export; unmatched coded values are flagged by the
validator.

## 6. Dates
ELSO wants `MM/DD/YYYY` (date) and `MM/DD/YYYY HH:MM` (datetime, no seconds). The engine
auto-detects common REDCap formats (`dd/mm/yyyy hh:mm:ss`, ISO `yyyy-mm-dd`, …), parses
to a real calendar time, and re-emits in ELSO's format. Example:
`31/01/2024 14:30:45` → `01/31/2024 14:30`.

## 7. De-identify (optional)
Off by default. When enabled you may pseudonymize chosen identifier columns (stable
tokens) and shift each patient's dates by a deterministic number of days (intervals
within a patient are preserved). The controller confirms adequacy before release.

## 8. Validate & generate
- **Validate** runs XSD structural validation + semantic QC (code membership, date parse,
  `UniqueId` length 10–20, numeric ranges). Errors should be resolved before upload;
  warnings are soft-range advisories.
- **Generate XML** builds the file, validates it, previews it, and (with a project open)
  writes it to `outputs/elso_import.xml` with a SHA-256 manifest and a log entry.

### Addenda upload profiles (Generate tab)
The main ELSO form is always emitted; the three addenda (Cardiac, ECPR 2020, Trauma) are
optional. Two controls let you choose which addenda a given upload carries:

- **Include addenda** checkboxes — tick the addenda to keep in the single **Generate XML**
  output. Any `*Addenda` block not ticked is pruned from the generated file after the build.
  Unticking all three yields a **main-only** file. This is a post-generation DOM prune, so it
  never changes the mapped data — the same field map produces every profile.
- **Generate all 8 combinations** button — writes all `2³` combinations at once
  (`main`; each addendum alone; each pair; all three) to
  `outputs/combinations/elso_import__<profile>.xml`, and shows a results table with per-file
  XSD validity and semantic-error counts. Use this to hand a center a full set of uploads, or
  to submit only the profiles a given run actually has.

Because the addenda attach to independent runs/patients, pruning one never affects another:
if the all-addenda file is portal-clean, every subset is too.

## Worked example (bundled sample)
1. Import → *Load bundled synthetic sample* (3 patients; PT-0002 has 2 runs).
2. Map → *Auto-suggest mapping*.
3. Grouping: patient key `.subject`, patient/hosp instrument `demographics`, run
   instrument `run`, run key `run_no`.
4. Sub-collections: Diagnoses ← `diagnosis` (link `dx_run`); Complications ←
   `complication` (link `comp_run`).
5. Validate → XSD valid, 0 errors. Generate → 3 `PatientXML`, 4 `RunXML`, dates in
   `MM/DD/YYYY`, codes recoded.

### Nested addenda (same bundled sample)
The sample also carries a Cardiac-addenda demo. In the **Cardiac addenda** block:
- Bind **CardiacCath** (the *Pre-ECLS* variant): instrument `cath`, link field
  `cc_run` (→ run key), **Key field** `cath_id`.
- Bind its nested **Diagnostic**: instrument `cath_dx`, link field `dx_cath`
  (→ the cath's `cath_id`).

Map `CathDateTime` ← `cath_dt`, `CathOption` ← `cath_option`, and the nested
`Diagnostic/CodeId` ← `cath_dx_code`. Generate → 3 `CardiacCath` (PT-0002 run 1 has
two) with 4 nested `Diagnostic` findings, and `CATH-1A` correctly carries two of them
— a repeating list inside a repeating list.

## Passing ELSO's import validator (XSD-valid is not enough)
The bundled XSD only checks structure; ELSO's **import** validator additionally rejects
**empty required fields** and **codes outside its lists**. A file can be XSD-valid yet
rejected. Two rules follow from this:

**1. Every run must carry the required collections — with real values.** ELSO requires,
per `RunXML`:
- `Modes / ConcurrentMode / Mode` — at least one mode with `StartTime`, `EndTime`, `ECLSMode`.
- `Equipment / {Pumps, MembraneLungs, Consoles}` — each device needs `DeviceId`,
  `AddedReplaced`, `StartTime`, `EndTime`.
- `ComplicationsEnabled` and `InfectionsEnabled` (0/1) on the run.

The converter never *invents* these — you must map them from your REDCap export. Any
required leaf left empty is flagged as an **error** on the Validate tab (and would be
rejected on upload). Optional collections you have no data for are simply omitted; the
generator drops an optional branch rather than emit empty required shells inside it.

**2. Codes must be real ELSO values.** `DiagnosisCode` is an ICD-10 code (e.g. `A00`,
`I47.2`); `ComplicationCode`, `ECLSMode`, device `DeviceId` and cath `CodeId` are ELSO
numeric codes. Do not recode them to arbitrary integers — map the actual code through, or
crosswalk on the Recode tab. Coded values outside the ELSO list are flagged as errors.

### The bundled sample is a complete, upload-valid example
`samples/make_sample_redcap.R` now includes `mode`, `pumps`, `lungs`, `consoles`
instruments and valid codes, so the bundled sample can produce a file that passes the
public XSD test portal (`registry.elso.org/xmlimporttestpublic`). `samples/sample_mapping.json`
is a ready-made mapping template for it: after **Load bundled synthetic sample**, set the
grouping keys and sub-collection bindings (below), then **Load template** to fill the
field map/recodes/date-formats in one step, and **Generate**.

Grouping: patient key `.subject`, patient/hosp `demographics`, run `run`, run key `run_no`.
Bind: Diagnoses←`diagnosis`(`dx_run`), Complications←`complication`(`comp_run`),
Modes/ConcurrentMode/Mode←`mode`(`mode_run`),
Equipment/Pumps/…/Device←`pumps`(`pump_run`),
Equipment/MembraneLungs/…/Device←`lungs`(`lung_run`),
Equipment/Consoles/…/Device←`consoles`(`console_run`),
CardiacCath←`cath`(`cc_run`, key `cath_id`), nested Diagnostic←`cath_dx`(`dx_cath`),
Cardiac2022ContributingDiagnosis←`cardiac_dx`(`cdx_run`),
TraumaAddenda ECLSIndicationTrauma←`trauma_ind`(`tind_run`),
TraumaRelatedInjury←`trauma_inj`(`tinj_run`),
ECPR2020Addenda AntecedentEvent←`ecpr_ante`(`ea_run`), CMcondition←`ecpr_cmc`(`ec_run`),
ECPRMedication←`ecpr_med`(`em_run`). (All of the above are already wired in
`sample_mapping.json`; **Load template** applies them in one step.)

### Verified against the ELSO public test portal
The bundled sample + `sample_mapping.json` were uploaded to
`registry.elso.org/xmlimporttestpublic` and **accepted with zero errors and zero warnings**.
All **eight** addenda combinations (main only; +Cardiac; +ECPR; +Trauma; and every mix up to
Cardiac+ECPR+Trauma) were each uploaded and cleared. The portal enforces far more than the
XSD; the minimum every run needs, learned there:

- **RunInfo:** `AdmissionWeight`, `AdmissionHeight`.
- **PreECLSAssessment and ECLSAssessment:** `BloodGas/pH`, `BloodGas/HCO3`,
  `VentSetting/VentilatorType`, `Hemodynamic/SBP`, `Hemodynamic/DBP` (the paired
  `*Unknown` flags set to `0`).
- **PreECLSSupport:** `MechanicalScUsed`, `RenPulOtherScUsed`, `MedicationsScUsed`,
  `VasoactivelScUsed` — set `0` for "none"; setting `1` then requires a support-code sub-list.
- **Diagnoses:** at least one `Diagnosis` per run, exactly one with `Primary = 1`.
- **Complications:** point complications (e.g. `541`) use `ComplicationDate`; *duration*
  complications (e.g. `201`) instead require `StartTime` + `EndTime`.
- **Hospitalization:** a discharged-alive patient needs `DischargeDate` + `DischargeLocation`.
- **CardiacAddenda (if present):** `NYHACategory`, `SCAIcAdmission`, `SCAIcPreECMO`,
  `ECLSCannulation`, `VasoactiveIntScore`, `CannulationLocation` (code `5` = ICU also needs
  `IntensiveCareSetting`), `PrecipitatingEvent`, `PreCathYesNo`/`DuringCathYesNo`/
  `AfterCathYesNo`, ≥1 `Cardiac2022ContributingDiagnosis/CodeId` (avoid the graft-failure
  code unless you also supply graft fields), and the VAD trio `VADEstimatedUnknown` (flag —
  only `1` is accepted), `VADDateImplementation`, `VADTempSupp`.
- **CardiacCath:** `CathOption` 1 = diagnostic-only, 2 = intervention-only (Interventions
  required), 3 = both. A pre-ECLS cath's `CathDateTime` must be **before** the ECLS mode
  start. Diagnostic code `5` (coronary dilation/stent) must be accompanied by its `3` sub-code.
- **ECPR2020Addenda (if present):** the portal requires a large, interlocking set once the
  block appears. Scalars: `PrecipitatingEvent` (its code list differs from CardiacAddenda's —
  `6` is valid for Cardiac but **not** ECPR; use an ECPR code such as `1`), `WitnessedArrest`,
  `ArrestDateTime`, `InitialPulselessRhythm`, `RhythmAtTimeCannulation`, `CPRFeedbackDevice`
  (must be `1` for `CPR` to be accepted), `CPR` (minutes, hard range 20–200 / soft 40–160),
  `SignsOfLifePreECLS`, `NeuromuscularBlockadeUse`, and a neurology selection
  (`NeurologyNoNeurologicInvestigation`). **Location of arrest** has two questions — set an
  in-hospital *or* out-of-hospital option for each; the `*ICUDesc` specify field is valid only
  when the chosen location option is the ICU one (e.g. `LAInHospital = 5` alongside `LAICUDesc`).
  Monitoring answers pull in a value: `EndTidalCO2Monitoring = 1` requires `ETCO2`;
  `InvasiveArterialAccess = 1` requires `DBPflowStart` (soft range 5–110); `CerebralNIRS = 1`
  requires `NIRS`; `TempManagement = 1` requires `HighestTemp24Hrs`. Lists needing ≥1 entry:
  `AntecedentEvents/AntecedentEvent/EventId`, `CMconditions/CMcondition/ConditionId`,
  `ECPRMedications/ECPRMedication/MedicationId`.
- **TraumaAddenda (if present):** all nine AIS body-region rates are required, each `0`–`6`
  (`AISHead`, `AISFace`, `AISNeck`, `AISThorax`, `AISAbdomen`, `AISSpine`, `AISUpperExtremity`,
  `AISLowerExtremity`, `AISExternalOther`), plus `PatientSurgicalProcedure`,
  `DamageControlSurgery`, `ReceivedBP24`, `ReceivedBP72`. The option code lists are **not
  uniform**: `DamageControlSurgery` rejects `0` (use `1` = Yes), whereas
  `PatientSurgicalProcedure`/`ReceivedBP24`/`ReceivedBP72` accept `0` = No. Choosing `0`/No on
  the surgical-procedure and blood-product questions avoids their nested sub-lists
  (`SurgInvProcedure`, PRBC/FFP/platelet quantities).

> Addenda code lists are **not** in the bundled lookups workbook (only the main-form
> collections are), so they are not caught by the offline validator — they are enforced only
> by the portal. The known-good values above were confirmed empirically against the test
> portal and mirror ELSO's own `docs/elso_spec/elso_sample.xml`.
