# REDCap → ELSO XML Converter

An **R Shiny** tool that turns a REDCap export into a valid **ELSO Registry import XML**
(`PatientList`, `urn:run-schema`) ready for upload. You map your REDCap fields to the
ELSO element tree in the app, recode coded values, optionally de-identify, validate, and
download the XML.

> ⚠️ **Not for clinical or diagnostic use.** Research/governance tool. The data
> controller is responsible for confirming each file before uploading to ELSO.
> **Never** load real patient data into the repo — use the synthetic `samples/` only.

## Features
- **Reads REDCap ODM XML** (metadata + records in one file) or **CSV + data dictionary**.
- **Interactive field mapping** with auto-suggest, grouping keys (patient / run), and
  reusable **JSON mapping templates**.
- **Multi-run per patient**: longitudinal / repeating-instrument REDCap collapses into
  `PatientXML → RunXML`, with repeating instruments bound to ELSO run-level collections
  (Diagnoses, Complications, Infections, …) and to the **Cardiac / ECPR / Trauma addenda**
  lists — including lists nested inside another (e.g. a catheterisation's diagnostics).
- **Value recoding** auto-crosswalked where REDCap choice labels match ELSO code-list
  labels.
- **Date engine**: parses REDCap dates (e.g. `dd/mm/yyyy hh:mm:ss`) and emits ELSO
  `MM/DD/YYYY` / `MM/DD/YYYY HH:MM` (seconds dropped, calendar-validated).
- **Optional de-identification** (off by default): stable ID pseudonyms + per-patient
  date shift.
- **Validation**: XSD structural validation + semantic QC (code membership, date parse,
  `UniqueId` length, numeric ranges).
- **Full ELSO dataset coverage** from a catalogue generated from the official XSD +
  lookups workbook (356 elements, incl. Cardiac / ECPR / Trauma addenda).
- **Portable, no-network, air-gap friendly**: pure R; a project lives in one folder.

## Run (development)
```bash
Rscript -e "shiny::runApp('app', port=7788)"
```
Open http://127.0.0.1:7788. On the **Import** tab, click *Load bundled synthetic sample*
to try it without a file.

Regenerate the synthetic sample:
```bash
Rscript samples/make_sample_redcap.R
```
Rebuild the ELSO catalogue after a spec update (run from the repo root):
```bash
Rscript tools/build_elso_catalogue.R
```

## Workflow (7 tabs)
1. **Project** — create/open a portable project folder (+ Center No.).
2. **Import REDCap** — load ODM XML or CSV; preview dictionary + records.
3. **Map fields** — grouping keys, sub-collection bindings, field mapping (auto-suggest,
   save/load template).
4. **Recode values** — review REDCap→ELSO code crosswalks.
5. **De-identify** — optional pseudonymize + date shift.
6. **Validate** — XSD + semantic issues.
7. **Generate XML** — build, preview, download; written to the project with a manifest.

## Status
Core proven end-to-end on synthetic data and smoke-tested through the UI (XSD valid, 0
semantic errors). See [CLAUDE.md](CLAUDE.md) and [docs/mapping-guide.md](docs/mapping-guide.md).
