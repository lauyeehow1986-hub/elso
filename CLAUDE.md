# CLAUDE.md — REDCap → ELSO XML Converter

## What this is
An **R Shiny tool that converts a REDCap export into ELSO Registry import XML** for
upload. The operator loads a REDCap **CDISC ODM XML** export (CSV + data-dictionary
also supported), **maps** their REDCap fields to the ELSO element tree, **recodes**
coded values, optionally **de-identifies**, **validates**, and generates a
schema-valid `PatientList` XML file.

Research/governance tool — **not for clinical or diagnostic use**. The data controller
remains responsible for confirming the file before uploading to ELSO. **Never commit
real patient data** — only synthetic samples under `samples/`.

## The ELSO target format (spec dated 01-05-2026)
- Root `PatientList` with `xmlns="urn:run-schema"`, UTF-8.
- Hierarchy: `PatientList → PatientXML → HospitalizationList/HospitalizationXML →
  RunList/RunXML`, with run-level repeating collections (Diagnoses, Complications,
  Infections, Procedures, Modes, Cannulations, Equipment devices) and optional
  `CardiacAddenda` / `ECPR2020Addenda` / `TraumaAddenda`.
- Patient key `UniqueId` (10–20 chars); each patient can have multiple `RunXML` (keyed
  by `RunNo`) — matches longitudinal / repeating-instrument REDCap projects.
- Dates `MM/DD/YYYY`; datetimes `MM/DD/YYYY HH:MM` (**seconds dropped**).
- **Every XSD leaf is `xsd:string`** — the schema enforces only element
  presence/nesting/order (+ `UniqueId` length). Code lists, date formats and numeric
  ranges live in the lookups workbook and are enforced by `app/R/validate.R`, NOT by
  `xml2::xml_validate`.

## Design principle — data-driven, not hard-coded
A bundled **catalogue** (`app/data/elso_catalogue.rds`) generated from the official XSD
drives the mapping-target tree, the generator's element order, and validation. Code
lists + ranges come from the lookups workbook (`elso_codelists.rds`, `elso_ranges.rds`).
"Full ELSO coverage" is therefore a matter of catalogue *data*, not new code — the
engine emits any leaf in the catalogue. Rebuild after an ELSO spec update with
`tools/build_elso_catalogue.R`.

## Tech stack
Pure R (R 4.5.x) + `shiny` + `bslib` + `DT`; `xml2` for ODM parsing, XML generation and
XSD validation; `readxl` for CSV/XLSX + the offline catalogue build; `jsonlite` for
mapping templates; `openssl` for de-id tokens + SHA-256 manifest. **No network calls**;
portable (`run.ps1`/`run.bat`), one self-contained project folder.

## Project layout
```
app/
  app.R            Shiny UI + server (7 tabs)
  global.R         loads app/R/*.R in dependency order
  R/
    util.R         helpers + date/datetime engine (parse -> ELSO MM/DD/YYYY[ HH:MM])
    catalogue.R    load bundled catalogue + code-list/section accessors
    redcap.R       parse REDCap ODM XML and CSV(+dictionary) -> dictionary + long records
    grouping.R     collapse records into Patient -> Hospitalization -> Run (+ nested sub-collections)
    mapping.R      auto-suggest map, label-based value recode, JSON template save/load
    generate.R     walk catalogue tree -> ELSO XML (required-empty + required-repeat rules); XSD validate
    validate.R     semantic QC: code membership, date parse, UniqueId length, ranges
    deident.R      OPTIONAL pseudonymize IDs + per-patient date shift (off by default)
    project.R      portable project folder + SHA-256 manifest + JSONL log
  data/            elso_catalogue.rds, elso_codelists.rds, elso_ranges.rds, elso_import.xsd (bundled)
tools/
  build_elso_catalogue.R   offline: XSD + lookups workbook -> app/data/*.rds
docs/
  elso_spec/       official XSD / lookups / sample (reference; source of the catalogue)
  mapping-guide.md
samples/
  make_sample_redcap.R     synthetic ECMO REDCap ODM + CSV generator (NO real data)
run.ps1 / run.bat
```

## Conventions
- **R**, `snake_case`, `el_` prefix on all core functions. Core (`app/R/*.R`) is pure and
  headless-testable — the generator/validator run without Shiny.
- The generator emits in **XSD declaration order** (satisfies both `xsd:sequence` and
  `xsd:all`). Required containers are always emitted (empty if unmapped); a required
  repeating element with no rows emits one empty instance. This keeps output XSD-valid
  from even a sparse mapping.
- A node repeats (consumes a scope collection) only when its path is a genuine **repeat
  level** (`unique(leaves$repeat_level)`). Some ELSO list *wrappers* (e.g.
  `CardiacCath/Diagnostics`) are themselves `maxOccurs="unbounded"` but are not repeat
  levels — they emit once and pass the scope through to the real inner element
  (`Diagnostic`). Nested sub-collections (a list inside another list) attach to their
  parent list's instances via a per-row **key field**; the generator already walks
  arbitrary depth, so grouping only has to build each instance's own `coll`.
- xml2 quirk: children built with `xml_add_child` aren't bound to the default namespace
  in-memory — `el_generate_xml` re-parses the serialized string so `xml_validate` sees
  `urn:run-schema` (the serialized file was always correct).
- Grouping selects use `selectize = FALSE` (native `<select>`) — reliable and simpler.

## Build & run (dev)
- App: `& "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" -e "shiny::runApp('app', port=7788)"`
- Rebuild catalogue: `Rscript tools/build_elso_catalogue.R` (run from repo root)
- Regenerate synthetic sample: `Rscript samples/make_sample_redcap.R`
- ⚠️ On this machine, multiline `Rscript -e` **segfaults** — put test code in a script file.

## Status
Core proven end-to-end on synthetic data: ODM parse → auto-map → group (multi-run per
patient) → generate → **XSD valid, 0 semantic errors**, and browser-smoke-tested through
the Shiny UI. Full-dataset catalogue (356 leaves, 83 required, 75 coded) built from the
official spec.

## Repo
`origin` = https://github.com/lauyeehow1986-hub/elso.git (branch
`claude/redcap-elso-xml-converter-ee14cb`).
