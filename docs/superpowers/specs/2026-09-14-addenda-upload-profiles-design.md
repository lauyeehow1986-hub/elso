# Design — Addenda upload profiles (all 8 combinations)

Date: 2026-09-14
Status: implemented 2026-09-15 (commit bb29c14). All 8 addenda combinations verified
clean on the ELSO public test portal (registry.elso.org/xmlimporttestpublic) — zero
errors, zero warnings — and both headless test suites pass.

## Goal

Let the operator produce a distinct, upload-valid ELSO import file for **every
combination of the three optional addenda**. The main ELSO form is always present;
the three addenda (Cardiac, ECPR 2020, Trauma) are each independently in or out, so
there are `2^3 = 8` files:

| # | Profile | `include` tokens | Filename token |
|---|---------|------------------|----------------|
| 1 | Main only | `()` | `main` |
| 2 | Main + Cardiac | `cardiac` | `cardiac` |
| 3 | Main + ECPR | `ecpr` | `ecpr` |
| 4 | Main + Trauma | `trauma` | `trauma` |
| 5 | Main + Cardiac + ECPR | `cardiac,ecpr` | `cardiac_ecpr` |
| 6 | Main + Cardiac + Trauma | `cardiac,trauma` | `cardiac_trauma` |
| 7 | Main + ECPR + Trauma | `ecpr,trauma` | `ecpr_trauma` |
| 8 | Main + Cardiac + ECPR + Trauma | `cardiac,ecpr,trauma` | `cardiac_ecpr_trauma` |

The operator can (a) pick any combination for the single Generate/Download, and
(b) generate all 8 at once into the project outputs folder.

## Background (current behaviour)

Addenda are emitted **implicitly** today. `el_emit` (`app/R/generate.R:114-122`)
drops any optional group holding no real text (`el_has_value`), so
`CardiacAddenda` / `ECPR2020Addenda` / `TraumaAddenda` appear only where the mapped
data populates them. There is one Generate button producing one `elso_import.xml`.
The bundled sample is already portal-clean for the main form + Cardiac addendum
(commit `4ad138d`); ECPR and Trauma carry no sample data yet.

Catalogue sizes (from `el_leaves`): CardiacAddenda 53 leaves, ECPR2020Addenda 60,
TraumaAddenda 44. The XSD marks nearly all addenda leaves optional; the portal's
**conditional-required** rules are not in the catalogue and are learned by iterating
uploads (as was done for Cardiac).

## Approach

**Post-generation prune + profile selector + batch.** A single pure DOM transform
removes the addenda subtrees not in the chosen set, applied *after* the existing
generator runs. The proven generator walk, grouping, validator, and mapping engine
are untouched.

Rejected alternatives:
- *Filter during generation* — threads an `include` flag through the recursive
  `el_emit` walk; more regression surface on proven code for no user-visible gain.
- *Eight mapping templates* — no batch, cannot suppress an addendum when data
  exists, pushes combinatorics onto the operator.

## Components

### 1. Engine — `app/R/generate.R`

```
el_addenda_tokens()        # named chr: c(cardiac="CardiacAddenda",
                           #              ecpr="ECPR2020Addenda",
                           #              trauma="TraumaAddenda")

el_addenda_combinations()  # list of 8 profiles in stable order, each
                           #   list(include=<chr tokens>, token=<filename token>,
                           #        label=<human label>)
                           # order: main, cardiac, ecpr, trauma, cardiac_ecpr,
                           #        cardiac_trauma, ecpr_trauma, cardiac_ecpr_trauma

el_apply_addenda_profile(doc, include = c("cardiac","ecpr","trauma"))
                           # remove every *Addenda element whose token is NOT in
                           # `include`, wherever it appears (any RunXML); return doc.
                           # include = character(0) -> main-only.
```

Implementation notes:
- Operates on a namespaced doc; select nodes by `local-name()` (e.g.
  `//*[local-name()='ECPR2020Addenda']`) to avoid the `urn:run-schema` prefix issue.
- Removes with `xml2::xml_remove`. Idempotent; removing an absent addendum is a
  no-op. Does not re-order or otherwise touch retained nodes.
- Returns the same doc object (mutated) for chaining; callers that need the original
  intact pass a copy (`read_xml(as.character(doc))`).

### 2. UI — Generate tab (`app/app.R`, tab 7)

- `checkboxGroupInput("addenda_incl", "Include addenda",
     c("Cardiac"="cardiac","ECPR 2020"="ecpr","Trauma"="trauma"),
     selected = c("cardiac","ecpr","trauma"), inline = TRUE)`.
  `do_generate()` (or a wrapper) applies `el_apply_addenda_profile(doc,
  input$addenda_incl)` before it becomes `rv$doc`, so the single generated file,
  the preview, the download, and Validate all reflect the ticked addenda.
- `actionButton("btn_generate_all", "Generate all 8 combinations")`:
  - Requires an open project (same guard the single Generate uses to write to
    disk); if none, notify and stop.
  - Builds the full doc once, then for each of the 8 profiles: copy the doc, prune
    to the profile, XSD-validate + semantic-check, and write
    `outputs/combinations/elso_import__<token>.xml`.
  - Writes a manifest (`el_manifest_write`) and a per-run log entry.
  - Renders a results table: profile label · XSD valid · #semantic errors ·
    filename. A muted note repeats: synthetic data, ELSO **test** portal only.
- No new download dependency: the 8 files land in the project outputs folder,
  consistent with today's single-Generate behaviour. (A zip download is explicitly
  out of scope to avoid a new package.)

### 3. Sample + mappings — `samples/make_sample_redcap.R`, `samples/sample_mapping.json`

- Add ECPR-2020 and Trauma content to the synthetic sample on at least one run
  each (flat run-level scalars + the addenda's nested-list instruments), with valid
  ELSO codes.
- Add explicit per-path mappings for the new leaves to `sample_mapping.json`
  (auto-suggest cannot disambiguate repeated leaf names across collections).
- Regenerate `sample_redcap.odm.xml`, `_records.csv`, `_dictionary.csv`,
  `sample_mapping.json`.

### 4. Docs — `docs/mapping-guide.md`

Add ECPR-2020 and Trauma conditional-required checklists (mirroring the Cardiac
section), populated from what the portal enforces during iteration. Note the new
addenda-profile selector and the "Generate all 8 combinations" batch.

## Data flow

```
parsed + binding + map/recode/datefmt
        │  el_build_hierarchy → el_generate_xml   (unchanged)
        ▼
   full doc (may contain all 3 addenda)
        │  el_apply_addenda_profile(doc, include)  (new, pure)
        ▼
   profile doc  → el_validate_xsd + el_semantic_check → write outputs/…__<token>.xml
```

Single Generate: `include = input$addenda_incl`.
Batch: loop `el_addenda_combinations()`, one pruned copy per profile.

## Error handling

- Batch with no project open → `showNotification(type="error")`, no writes.
- A profile that fails XSD or has semantic errors is still written (so the operator
  can inspect it) but flagged red in the results table; the batch does not abort on
  one bad profile.
- Prune on a doc lacking a given addendum → no-op (expected for runs without that
  data; not an error).

## Verification

**Headless (`scratchpad/` harness, then a committed check):**
- `el_apply_addenda_profile` yields exactly the expected addenda per profile;
  main-only contains zero `*Addenda` elements.
- All 8 combinations are XSD-valid with 0 semantic errors.
- The `main` combination is byte-for-byte equivalent (modulo addenda) to today's
  passing baseline — i.e. no regression in the main form.
- Counts: retained addenda match the sample (e.g. `cardiac` keeps the 3
  `CardiacCath`; `main` keeps none).

**Portal:** upload all 8 files to `registry.elso.org/xmlimporttestpublic`
(Claude-in-Chrome `file_upload`), iterate red-font conditional errors to clean.

## Scope / boundaries

In scope: the prune transform, the selector + batch UI, sample ECPR/Trauma data,
per-path mappings, doc updates, headless + portal verification.

Out of scope: zip download; changes to the generator walk, grouping, validator, or
mapping engine; any real-data path. No new package dependencies.

## Constraints (standing)

- Never commit real patient data — synthetic only, under `samples/`.
- Research/governance tool, not for clinical use.
- Test portal is for synthetic data only; never the live registry.
- Multiline `Rscript -e` segfaults on this machine → use script files.
- ASK before pushing.
