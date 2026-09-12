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

## Worked example (bundled sample)
1. Import → *Load bundled synthetic sample* (3 patients; PT-0002 has 2 runs).
2. Map → *Auto-suggest mapping*.
3. Grouping: patient key `.subject`, patient/hosp instrument `demographics`, run
   instrument `run`, run key `run_no`.
4. Sub-collections: Diagnoses ← `diagnosis` (link `dx_run`); Complications ←
   `complication` (link `comp_run`).
5. Validate → XSD valid, 0 errors. Generate → 3 `PatientXML`, 4 `RunXML`, dates in
   `MM/DD/YYYY`, codes recoded.
