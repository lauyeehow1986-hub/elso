# Addenda Upload Profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the operator produce a distinct, upload-valid ELSO import XML for every combination of the three optional addenda (Cardiac, ECPR-2020, Trauma) — 8 files — via a Generate-tab profile selector plus a "generate all 8" batch, and make the bundled synthetic sample portal-clean for all three addenda.

**Architecture:** Keep the proven generator walk untouched. Add pure functions to `app/R/generate.R`: a profile pruner that removes the addenda subtrees not selected from an already-generated doc, and a batch driver that writes all 8 pruned+validated files. The Shiny Generate tab gets checkboxes (single file) and a batch button (all 8). The synthetic sample and its mapping template gain ECPR-2020 + Trauma content, then each combination is iterated against the ELSO public test portal until clean.

**Tech Stack:** R 4.5.2, `xml2` (DOM prune/validate), Shiny + bslib + DT. Headless tests are plain Rscript scripts using `stopifnot` (the repo has no testthat suite; core is pure and headless-testable per CLAUDE.md). ⚠️ Multiline `Rscript -e` segfaults on this machine — always run a script file.

**Conventions:** `el_` prefix, snake_case. Commit messages end with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Run every command from the worktree root `C:/Users/lauye/Downloads/elso/.claude/worktrees/redcap-elso-xml-converter-ee14cb`. Rscript is `"C:/Program Files/R/R-4.5.2/bin/Rscript.exe"`. Do NOT push — the user asks before pushes.

---

## File structure

- `app/R/generate.R` (modify) — add `el_addenda_tokens`, `el_addenda_combinations`, `el_apply_addenda_profile`, `el_generate_all_combinations`. Pure, headless-testable.
- `app/app.R` (modify) — Generate tab (tab 7): "Include addenda" checkboxes wired into `do_generate`; a "Generate all 8 combinations" button + results table.
- `samples/make_sample_redcap.R` (modify) — add ECPR-2020 and Trauma instruments/scalars on representative runs.
- `samples/sample_mapping.json` (regenerate) — explicit per-path mappings for the new leaves.
- `samples/sample_redcap.odm.xml`, `samples/sample_redcap_records.csv`, `samples/sample_redcap_dictionary.csv` (regenerate).
- `tests/test_addenda_profile.R` (create) — unit checks for the pure profile functions.
- `tests/test_all_combinations.R` (create) — end-to-end check that all 8 combinations build XSD-valid with 0 semantic errors from the bundled sample.
- `docs/mapping-guide.md` (modify) — ECPR-2020 + Trauma conditional-required checklists; document the selector + batch.

---

## Task 1: Pure addenda-profile functions

**Files:**
- Modify: `app/R/generate.R` (append functions after `el_write_xml`)
- Test: `tests/test_addenda_profile.R`

- [ ] **Step 1: Write the failing test**

Create `tests/test_addenda_profile.R`:

```r
# Headless unit checks for the addenda-profile pruner.
# Run from the repo root:
#   "C:/Program Files/R/R-4.5.2/bin/Rscript.exe" tests/test_addenda_profile.R
suppressWarnings(source("app/global.R"))

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

cat("test_addenda_profile: PASS\n")
```

Note: the `setwd(...)` first line is a defensive no-op; the runner is always launched from the repo root, so `source("app/global.R")` resolves. If it errors, replace the first line with nothing and rely on the run-from-root invocation.

- [ ] **Step 2: Run it to verify it fails**

Run: `"C:/Program Files/R/R-4.5.2/bin/Rscript.exe" tests/test_addenda_profile.R`
Expected: FAIL — `could not find function "el_addenda_tokens"`.

- [ ] **Step 3: Implement the functions**

Append to `app/R/generate.R` (after `el_write_xml`, end of file):

```r
# ---- addenda upload profiles ------------------------------------------------
# The three optional run-level addenda, as token -> element local-name.
el_addenda_tokens <- function()
  c(cardiac = "CardiacAddenda", ecpr = "ECPR2020Addenda", trauma = "TraumaAddenda")

# The 8 profiles (main form always present; each addendum in or out), in a
# stable order. Each is list(include=<tokens>, token=<filename token>, label=).
el_addenda_combinations <- function() {
  toks <- names(el_addenda_tokens())            # cardiac, ecpr, trauma
  # subsets ordered by size then by the toks order, matching the design table
  order_tokens <- list(
    character(0), "cardiac", "ecpr", "trauma",
    c("cardiac","ecpr"), c("cardiac","trauma"), c("ecpr","trauma"),
    c("cardiac","ecpr","trauma"))
  lbl <- c(cardiac = "Cardiac", ecpr = "ECPR 2020", trauma = "Trauma")
  lapply(order_tokens, function(inc) {
    tok <- if (length(inc) == 0L) "main" else paste(inc, collapse = "_")
    label <- if (length(inc) == 0L) "Main only"
             else paste("Main +", paste(unname(lbl[inc]), collapse = " + "))
    list(include = inc, token = tok, label = label)
  })
}

# Remove every *Addenda subtree whose token is NOT in `include`, wherever it
# appears. Mutates and returns `doc`. include=character(0) -> main-only.
# Select by local-name() because the doc is default-namespaced (urn:run-schema).
el_apply_addenda_profile <- function(doc, include = names(el_addenda_tokens())) {
  toks <- el_addenda_tokens()
  drop <- toks[setdiff(names(toks), include)]
  for (ln in drop) {
    nodes <- xml2::xml_find_all(doc, sprintf("//*[local-name()='%s']", ln))
    if (length(nodes)) xml2::xml_remove(nodes)
  }
  doc
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `"C:/Program Files/R/R-4.5.2/bin/Rscript.exe" tests/test_addenda_profile.R`
Expected: `test_addenda_profile: PASS`

- [ ] **Step 5: Commit**

```bash
git add app/R/generate.R tests/test_addenda_profile.R
git commit -m "Add pure addenda-profile pruner + 8-combination enumerator

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Batch driver `el_generate_all_combinations`

**Files:**
- Modify: `app/R/generate.R`
- Test: `tests/test_addenda_profile.R` (extend)

- [ ] **Step 1: Write the failing test**

Append to `tests/test_addenda_profile.R` before the final `cat(...)`:

```r
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `"C:/Program Files/R/R-4.5.2/bin/Rscript.exe" tests/test_addenda_profile.R`
Expected: FAIL — `could not find function "el_generate_all_combinations"`.

- [ ] **Step 3: Implement**

Append to `app/R/generate.R`:

```r
# Build the full doc once, then write one pruned+validated file per profile.
# Returns a data.frame(profile,label,token,xsd_valid,n_error,file). Each file is
# written even if invalid, so the operator can inspect failures.
el_generate_all_combinations <- function(cat, hierarchy, map = list(),
                                          recode = list(), datefmt = list(),
                                          out_dir, xsd_path,
                                          prefix = "elso_import__") {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  full_str <- as.character(el_generate_xml(cat, hierarchy, map, recode, datefmt))
  combos <- el_addenda_combinations()
  rows <- lapply(combos, function(cb) {
    doc <- el_apply_addenda_profile(read_xml(full_str), cb$include)
    xsd <- el_validate_xsd(doc, xsd_path)
    iss <- tryCatch(el_semantic_check(cat, doc),
                    error = function(e) data.frame())
    n_err <- if (is.data.frame(iss) && nrow(iss))
      sum(iss$severity == "error", na.rm = TRUE) else 0L
    fn <- file.path(out_dir, paste0(prefix, cb$token, ".xml"))
    el_write_xml(doc, fn)
    data.frame(profile = cb$label, token = cb$token,
               xsd_valid = isTRUE(xsd$ok), n_error = as.integer(n_err),
               file = basename(fn), stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `"C:/Program Files/R/R-4.5.2/bin/Rscript.exe" tests/test_addenda_profile.R`
Expected: `test_addenda_profile: PASS` and `test batch: PASS`.

- [ ] **Step 5: Commit**

```bash
git add app/R/generate.R tests/test_addenda_profile.R
git commit -m "Add el_generate_all_combinations batch driver

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Generate-tab addenda checkboxes (single file)

**Files:**
- Modify: `app/app.R` (UI tab 7 ~line 122-127; `do_generate` ~line 328-339)

- [ ] **Step 1: Add the checkbox UI**

In `app/app.R`, inside the `nav_panel("7 \u00b7 Generate XML", ...)` card, add the checkbox group above the button row (before the `div(actionButton("btn_generate", ...))`):

```r
      checkboxGroupInput("addenda_incl", "Include addenda",
        c("Cardiac" = "cardiac", "ECPR 2020" = "ecpr", "Trauma" = "trauma"),
        selected = c("cardiac", "ecpr", "trauma"), inline = TRUE),
      div(class = "small text-muted mb-2",
          "Untick an addendum to omit it from the generated file. ",
          "The main ELSO form is always included."),
```

- [ ] **Step 2: Apply the profile in `do_generate`**

In `app/app.R`, change the last line of `do_generate()` (currently
`el_generate_xml(CAT, hier, rv$map, rv$recode, rv$datefmt)`) to:

```r
    doc <- el_generate_xml(CAT, hier, rv$map, rv$recode, rv$datefmt)
    el_apply_addenda_profile(doc, input$addenda_incl %||% names(el_addenda_tokens()))
```

(`input$addenda_incl` is `NULL` until the input registers; the `%||%` default keeps all three, matching the checkbox default.)

- [ ] **Step 3: Verify in the browser**

Launch: `"C:/Program Files/R/R-4.5.2/bin/Rscript.exe" -e "shiny::runApp('app', port=7788)"` (background), open the Browser pane at `http://localhost:7788`.
- Project tab → set folder `<scratchpad>/elso_job`, Create.
- Import → Load bundled synthetic sample.
- Map → Auto-suggest; set grouping keys + bindings per `docs/mapping-guide.md` worked example (or Load template `samples/sample_mapping.json`).
- Generate tab → untick ECPR + Trauma, Generate. Read `xml_preview` (or the written file) and confirm no `ECPR2020Addenda` / `TraumaAddenda`, but `CardiacAddenda` present.
Expected: the single file honours the ticks.

- [ ] **Step 4: Commit**

```bash
git add app/app.R
git commit -m "Generate tab: addenda include checkboxes drive the single file

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: "Generate all 8 combinations" batch button

**Files:**
- Modify: `app/app.R` (UI tab 7; server generate section ~line 363-389)

- [ ] **Step 1: Add the button + table to the UI**

In the Generate tab card, after the existing button row, add:

```r
      hr(),
      div(actionButton("btn_generate_all", "Generate all 8 combinations",
                       class = "btn-outline-primary"),
          span(class = "small text-muted ms-2",
               "Writes 8 files to <project>/outputs/combinations/. ",
               "Synthetic data \u2014 ELSO test portal only.")),
      DTOutput("combo_tbl"),
```

- [ ] **Step 2: Add the server handler**

In `app/app.R` server, after the `observeEvent(input$btn_generate, {...})` block, add:

```r
  rv_combo <- reactiveVal(NULL)
  observeEvent(input$btn_generate_all, {
    proj_dir <- rv$proj$dir %||% input$proj_dir
    if (is.null(rv$proj) || el_blank(proj_dir)) {
      showNotification("Open or create a project first (files are written to its outputs folder).",
                       type = "error"); return(invisible())
    }
    req(rv$parsed)
    parsed <- rv$parsed
    if (isTRUE(input$deid_on))
      parsed$records <- el_apply_deident(parsed$records, list(
        secret = input$deid_secret, id_cols = input$deid_ids, date_cols = input$deid_dates,
        max_shift_days = input$deid_shift, patient_key = input$patient_key %||% ".subject"))
    rv$binding <- build_binding()
    hier <- el_build_hierarchy(parsed, rv$binding)
    out_dir <- file.path(el_project_paths(proj_dir)$outputs, "combinations")
    res <- tryCatch(
      el_generate_all_combinations(CAT, hier, rv$map, rv$recode, rv$datefmt,
                                   out_dir = out_dir, xsd_path = getOption("el.xsd_path")),
      error = function(e) { showNotification(conditionMessage(e), type = "error"); NULL })
    req(res)
    rv_combo(res)
    el_manifest_write(proj_dir)
    el_log_append(proj_dir, "generate_all",
                  list(n = nrow(res), n_xsd_ok = sum(res$xsd_valid),
                       n_clean = sum(res$xsd_valid & res$n_error == 0)))
    showNotification(sprintf("Wrote %d combination files to %s", nrow(res), out_dir),
                     type = "message")
  })
  output$combo_tbl <- renderDT({
    res <- rv_combo(); if (is.null(res)) return(NULL)
    datatable(res, rownames = FALSE, options = list(dom = "t", pageLength = 8)) |>
      formatStyle("xsd_valid", target = "row",
                  backgroundColor = styleEqual(c(TRUE, FALSE), c("#d1e7dd", "#f8d7da"))) |>
      formatStyle("n_error", color = styleInterval(0, c("inherit", "#b02a37")))
  })
```

- [ ] **Step 3: Verify in the browser**

With the app running and the sample loaded/mapped (Task 3 setup), click "Generate all 8 combinations".
Expected: notification of 8 files; `combo_tbl` shows 8 rows; check `<scratchpad>/elso_job/outputs/combinations/` has `elso_import__main.xml` … `elso_import__cardiac_ecpr_trauma.xml`.

- [ ] **Step 4: Commit**

```bash
git add app/app.R
git commit -m "Generate tab: 'generate all 8 combinations' batch button + results table

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Add ECPR-2020 + Trauma data to the synthetic sample

**Files:**
- Modify: `samples/make_sample_redcap.R`

Follow the existing instrument pattern (see the `caths` / `cath_dx` / `cardiac_dx` blocks at `samples/make_sample_redcap.R:81-110`, the `dd` dictionary rbind blocks at `:163-230`, the `forms` vector `:282`, the `flat`/`bind_form` list `:250-260`, and the `subj_blocks`/`form_block` loops `:303-327`). Each new instrument needs: a data.frame, dictionary rows in `dd`, membership in `forms`, a `bind_form(...)` row in `flat`, and a `form_block(...)` loop in `subj_blocks`.

- [ ] **Step 1: List valid codes for the coded ECPR/Trauma leaves**

Create `scratchpad/dump_addenda_codes.R`:

```r
setwd("C:/Users/lauye/Downloads/elso/.claude/worktrees/redcap-elso-xml-converter-ee14cb")
suppressWarnings(source("app/global.R"))
cat <- el_load_catalogue(); lv <- el_leaves(cat)
for (grp in c("ECPR2020Addenda","TraumaAddenda")) {
  sub <- lv[grepl(paste0("/",grp,"/"), lv$path, fixed=TRUE) & isTRUE(lv$has_codes) |
             (grepl(paste0("/",grp,"/"), lv$path, fixed=TRUE) & lv$has_codes), ]
  cat("\n==== ", grp, " coded leaves ====\n")
  for (i in seq_len(nrow(sub))) {
    cl <- el_codelist(cat, sub[i,])
    codes <- if (!is.null(cl)) paste(utils::head(cl$code, 8), collapse=",") else "(none)"
    cat(sprintf("%s  codes: %s\n", sub$name[i], codes))
  }
}
```

Run: `"C:/Program Files/R/R-4.5.2/bin/Rscript.exe" scratchpad/dump_addenda_codes.R`
Record the valid first-code of each coded leaf you plan to populate. Use these real codes in Step 2 (do not invent integers).

- [ ] **Step 2: Add the ECPR-2020 instrument (flat run-level scalars)**

The ECPR addendum is mostly flat run-level fields (no required nested list to satisfy for a minimal valid block; nested lists are optional). Add an `ecpr` instrument keyed to a run. In `make_sample_redcap.R`, after the `cardiac_dx` block, add (fill coded values from Step 1; datetimes must be consistent with the run's ECLS start — arrest before cannulation):

```r
# ECPR-2020 addendum demo: attach to PT-0001 run (a non-cardiac run) so the
# combinations differ meaningfully. One row per run that has ECPR data.
ecpr <- data.frame(
  patient_id = "PT-0001", ecpr_run = "1",
  ecpr_precip = "<code>",          # PrecipitatingEvent
  witnessed_arrest = "1",           # WitnessedArrest (Yes)
  arrest_dt = "20/03/2024 07:30:00",# ArrestDateTime (before ECLS start)
  cpr = "1",                        # CPR performed
  total_cpr_time = "20/03/2024 08:10:00",
  init_rhythm = "<code>",           # InitialPulselessRhythm
  rosc = "<code>",                  # ROSCtimeAfterCPR
  stringsAsFactors = FALSE)
```

- [ ] **Step 3: Add the Trauma instrument (flat scalars + one related-injury row)**

```r
# Trauma addendum demo: attach to PT-0003 run. DateOfTrauma before ECLS start.
trauma <- data.frame(
  patient_id = "PT-0003", trauma_run = "1",
  trauma_dt = "24/03/2024 06:00:00",  # DateOfTrauma
  mech_blunt = "1", mech_penetrating = "0", mech_burns = "0",
  ais_head = "<code>", ais_thorax = "<code>",  # AIS region scores
  received_bp24 = "0",                # ReceivedBP24 (No -> avoids the volume sub-fields)
  stringsAsFactors = FALSE)
# nested TraumaRelatedInjury (one code per row, linked to the run)
trauma_inj <- data.frame(
  patient_id = "PT-0003", tinj_run = "1",
  tinj_code = "<code>",               # TraumaRelatedInjury/CodeId
  stringsAsFactors = FALSE)
```

- [ ] **Step 4: Register the new instruments in dictionary, forms, flat, subj_blocks**

- Add `dd` rbind blocks describing every new field (mirror the existing cardiac blocks at `:206-230`), with `form_name` set to `ecpr`, `trauma`, `trauma_inj` respectively.
- Add `"ecpr","trauma","trauma_inj"` to the `forms` vector (`:282`).
- Add to the `flat` rbind list (`:250`): `bind_form(ecpr,"ecpr")`, `bind_form(trauma,"trauma")`, `bind_form(trauma_inj,"trauma_inj")`.
- Add `subj_blocks` loops (mirror `:313-326`) for each new instrument, keyed by `patient_id == pid`.

- [ ] **Step 5: Regenerate the sample artifacts**

Run: `"C:/Program Files/R/R-4.5.2/bin/Rscript.exe" samples/make_sample_redcap.R`
Expected: writes `samples/sample_redcap.odm.xml`, `_records.csv`, `_dictionary.csv` with no error; console summary mentions the new instruments (add a `cat(...)` line summarising ECPR/Trauma like the existing cardiac summary at `:346`).

- [ ] **Step 6: Commit**

```bash
git add samples/make_sample_redcap.R samples/sample_redcap.odm.xml samples/sample_redcap_records.csv samples/sample_redcap_dictionary.csv
git commit -m "Add ECPR-2020 and Trauma addenda data to the synthetic sample

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Explicit per-path mappings for the new leaves

**Files:**
- Modify: `samples/sample_mapping.json` (regenerate via a scratchpad builder)

Auto-suggest maps by leaf name only and cannot disambiguate repeated names, so the ECPR/Trauma leaves need explicit per-path entries — the same approach the Cardiac leaves use in the existing template.

- [ ] **Step 1: Extend the mapping-template builder**

Reuse/extend `scratchpad/build_valid.R` (the existing headless builder that wrote `sample_mapping.json`). Add the ECPR/Trauma leaf paths to its parallel `paths`/`fields` vectors, e.g.:

```r
# ECPR-2020
paths  <- c(paths,  ".../RunXML/ECPR2020Addenda/PrecipitatingEvent",
                    ".../RunXML/ECPR2020Addenda/WitnessedArrest",
                    ".../RunXML/ECPR2020Addenda/ArrestDateTime", ...)
fields <- c(fields, "ecpr_precip", "witnessed_arrest", "arrest_dt", ...)
# Trauma
paths  <- c(paths,  ".../RunXML/TraumaAddenda/DateOfTrauma",
                    ".../RunXML/TraumaAddenda/MechanismBlunt", ...,
                    ".../RunXML/TraumaAddenda/TraumaRelatedInjuriesList/TraumaRelatedInjury/CodeId")
fields <- c(fields, "trauma_dt", "mech_blunt", ..., "tinj_code")
```

Also add the two new run-level bindings to `binding$subcollections` (ECPR has no repeat list to bind for the flat fields; Trauma's `TraumaRelatedInjury` binds to instrument `trauma_inj`, link `tinj_run`). Keep the const-0 `*Unknown`/flag leaves mapped to `list(const="0")` per the Cardiac precedent, EXCEPT any flag the portal requires to be `1` (discovered in Task 8).

Use the full paths printed by `scratchpad/dump_addenda.R` (already run) for exactness.

- [ ] **Step 2: Regenerate the template**

Run: `"C:/Program Files/R/R-4.5.2/bin/Rscript.exe" scratchpad/build_valid.R`
Expected: rewrites `samples/sample_mapping.json`; prints XSD valid TRUE and 0 empty-required / 0 semantic errors for the full (all-addenda) doc.

- [ ] **Step 3: Commit**

```bash
git add samples/sample_mapping.json scratchpad/build_valid.R
git commit -m "Map ECPR-2020 and Trauma leaves in the sample template

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: End-to-end headless check of all 8 combinations

**Files:**
- Create: `tests/test_all_combinations.R`

- [ ] **Step 1: Write the test**

Create `tests/test_all_combinations.R`:

```r
# End-to-end: bundled sample + sample_mapping.json -> all 8 combinations are
# XSD-valid with 0 semantic errors, and each retains exactly its addenda.
# Run: "C:/Program Files/R/R-4.5.2/bin/Rscript.exe" tests/test_all_combinations.R
suppressWarnings(source("app/global.R"))
parsed <- el_read_redcap_odm("samples/sample_redcap.odm.xml")
tmpl <- el_load_mapping("samples/sample_mapping.json")
hier <- el_build_hierarchy(parsed, tmpl$binding)
tmp <- file.path(tempdir(), "combo_e2e"); unlink(tmp, recursive = TRUE)
res <- el_generate_all_combinations(CAT, hier, tmpl$map, tmpl$recode, tmpl$datefmt,
                                    out_dir = tmp, xsd_path = getOption("el.xsd_path"))
print(res)
stopifnot(nrow(res) == 8L)
stopifnot(all(res$xsd_valid))          # every combination XSD-valid
stopifnot(all(res$n_error == 0L))      # every combination 0 semantic errors

# addenda presence per profile
has <- function(f, ln) length(xml2::xml_find_all(
  xml2::read_xml(file.path(tmp, f)), sprintf("//*[local-name()='%s']", ln))) > 0
stopifnot(!has("elso_import__main.xml","CardiacAddenda"),
          !has("elso_import__main.xml","ECPR2020Addenda"),
          !has("elso_import__main.xml","TraumaAddenda"))
stopifnot(has("elso_import__cardiac_ecpr_trauma.xml","CardiacAddenda"),
          has("elso_import__cardiac_ecpr_trauma.xml","ECPR2020Addenda"),
          has("elso_import__cardiac_ecpr_trauma.xml","TraumaAddenda"))
stopifnot(has("elso_import__cardiac.xml","CardiacAddenda"),
          !has("elso_import__cardiac.xml","ECPR2020Addenda"))
cat("test_all_combinations: PASS\n")
```

(Confirmed names: `el_read_redcap_odm` (app/R/redcap.R:19), `el_build_hierarchy` (app/R/grouping.R:90), `el_load_mapping` (app/R/mapping.R:93).)

- [ ] **Step 2: Run it**

Run: `"C:/Program Files/R/R-4.5.2/bin/Rscript.exe" tests/test_all_combinations.R`
Expected: prints the 8-row table, then `test_all_combinations: PASS`. If a semantic error appears for an addendum, fix the sample/mapping (Tasks 5-6) — this catches missing conditional content before the portal does.

- [ ] **Step 3: Commit**

```bash
git add tests/test_all_combinations.R
git commit -m "Add end-to-end all-8-combinations headless check

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: Portal iteration — make all 8 upload-clean

**Files:**
- Modify (as needed): `samples/make_sample_redcap.R`, `scratchpad/build_valid.R` → regenerate `samples/sample_mapping.json` + sample artifacts
- Modify: `docs/mapping-guide.md`

This is the exploratory loop — the ELSO test portal enforces conditional-required rules for ECPR/Trauma that are not in the catalogue (same as Cardiac). Iterate.

- [ ] **Step 1: Generate the 8 files from the bundled sample**

Either run the app's "Generate all 8 combinations" against a project, or run `tests/test_all_combinations.R` after pointing `out_dir` at a stable folder, so you have the 8 `.xml` files to upload.

- [ ] **Step 2: Upload each combination to the ELSO public test portal**

Use Claude-in-Chrome (the in-app Browser cannot set the portal's hidden file input). Load the core Chrome tools via one ToolSearch `select:` call. Navigate to `https://registry.elso.org/xmlimporttestpublic`, `file_upload` the file into `input[name='uploadXMLFile']`, submit, and read the result. Start with `elso_import__ecpr.xml` and `elso_import__trauma.xml` (the two new single-addendum files) — they isolate each addendum's rules.

- [ ] **Step 3: Fix red-font conditional errors**

Portal font colours: blue = "field required", red = conditional/consistency rule; both block. Green = soft advisory (non-blocking). For each blocking error, add/adjust the corresponding field in `samples/make_sample_redcap.R` and its per-path mapping in the `build_valid.R` builder, regenerate (`make_sample_redcap.R` then `build_valid.R`), re-run `tests/test_all_combinations.R`, and re-upload. Record each rule learned.

- [ ] **Step 4: Confirm all 8 pass**

Upload all 8 files; confirm every combination is accepted with zero blocking errors. The `main` file is already known-clean (baseline `4ad138d`); `cardiac` reproduces the prior Cardiac pass. Focus effort on ecpr, trauma, and their combinations.

- [ ] **Step 5: Document the ECPR/Trauma conditional rules**

In `docs/mapping-guide.md`, add "ECPR-2020 (if present)" and "Trauma (if present)" checklists mirroring the existing Cardiac checklist, listing exactly the conditional-required fields learned. Add a short "Addenda upload profiles" subsection describing the Generate-tab checkboxes and the "Generate all 8 combinations" batch (files land in `outputs/combinations/`).

- [ ] **Step 6: Commit**

```bash
git add samples/make_sample_redcap.R samples/sample_mapping.json samples/sample_redcap.odm.xml samples/sample_redcap_records.csv samples/sample_redcap_dictionary.csv scratchpad/build_valid.R docs/mapping-guide.md
git commit -m "Make all 8 addenda combinations pass the ELSO import test portal

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 9: Update memory + spec status; final verification

**Files:**
- Modify: `docs/superpowers/specs/2026-09-14-addenda-upload-profiles-design.md` (mark implemented)
- Modify: memory `project_elso_converter.md` + `MEMORY.md` (record the feature + portal pass)

- [ ] **Step 1: Re-run both headless tests**

Run: `"C:/Program Files/R/R-4.5.2/bin/Rscript.exe" tests/test_addenda_profile.R && "C:/Program Files/R/R-4.5.2/bin/Rscript.exe" tests/test_all_combinations.R`
Expected: both print PASS.

- [ ] **Step 2: Update spec status line** to `Status: implemented (commit <tip>)`.

- [ ] **Step 3: Update memory** — in `project_elso_converter.md` add a paragraph: addenda upload profiles shipped (pure `el_apply_addenda_profile` + `el_generate_all_combinations`; Generate-tab checkboxes + batch button; sample now carries ECPR-2020 + Trauma data; all 8 combinations pass the test portal), and refresh the `MEMORY.md` one-liner. Convert relative dates to absolute (2026-09-14).

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-09-14-addenda-upload-profiles-design.md
git commit -m "Mark addenda-upload-profiles spec implemented

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 5: Report to the user** — summarise the 8-combination results table and ASK before pushing (standing constraint).

---

## Notes / cautions

- Do NOT push; the user approves pushes explicitly. Do NOT touch the shared local `main` (structured_deid trunk); work stays on `elso-main`.
- Never commit real patient data — synthetic only.
- The test portal is for synthetic data only; never the live registry.
- `el_apply_addenda_profile` mutates its doc — always pass a fresh `read_xml(as.character(full))` per profile (the batch driver already does).
- Confirmed helper names: `el_read_redcap_odm`, `el_build_hierarchy`, `el_load_mapping`, `el_load_catalogue`, `el_semantic_check`, `el_validate_xsd`, `el_write_xml`, `el_manifest_write`, `el_log_append`, `el_project_paths`.
