# app.R — REDCap -> ELSO Registry XML converter (Shiny UI).
# Launch:  Rscript -e "shiny::runApp('app', port=7788)"   or run.ps1 / run.bat

local({
  cand <- c("global.R", file.path("app", "global.R"))
  hit <- cand[file.exists(cand)][1]
  if (is.na(hit)) stop("cannot locate global.R")
  source(hit, local = FALSE)
})

CAT <- el_load_catalogue()
LEAVES <- el_leaves(CAT)
LEAVES$section_label <- vapply(LEAVES$path, el_section_of, character(1))
SECTIONS <- unique(LEAVES$section_label)
# repeat collections the user can bind to a REDCap instrument (run-level + all
# Cardiac/ECPR/Trauma addenda repeat-lists, incl. ones nested inside another)
SUBCOLL_PATHS <- unique(LEAVES$repeat_level[
  vapply(LEAVES$repeat_level, el_level_kind, character(1)) == "subcollection"])

# group each binder for the UI: run-level vs the three addenda blocks
el_subcoll_group <- function(path) {
  if (grepl("/CardiacAddenda/", path, fixed = TRUE))   return("Cardiac addenda")
  if (grepl("/ECPR2020Addenda/", path, fixed = TRUE))  return("ECPR 2020 addenda")
  if (grepl("/TraumaAddenda/", path, fixed = TRUE))    return("Trauma addenda")
  "Run-level collections"
}
SUBCOLL_GROUP  <- vapply(SUBCOLL_PATHS, el_subcoll_group, character(1))
SUBCOLL_ORDER  <- c("Run-level collections", "Cardiac addenda",
                    "ECPR 2020 addenda", "Trauma addenda")
# nearest bound ancestor (structural, over all binders): "" == attaches to run
SUBCOLL_PARENT <- el_subs_parent_map(SUBCOLL_PATHS)
# a binder is a "parent" if some other binder nests under it -> needs a key field
SUBCOLL_IS_PARENT <- setNames(SUBCOLL_PATHS %in% SUBCOLL_PARENT, SUBCOLL_PATHS)

# readable label for a binder: container trail + element name
el_subcoll_label <- function(path) {
  paste0(el_section_of(path), " ▸ ", basename(path))
}

id_of <- function(path) paste0("m_", chartr("/", ".", path))

# ---- UI --------------------------------------------------------------------
ui <- page_navbar(
  title = "REDCap \u2192 ELSO XML", id = "nav",
  theme = bs_theme(version = 5, preset = "flatly"),
  sidebar = sidebar(width = 300,
    textInput("actor", "Your name / ID", value = Sys.getenv("USERNAME", "operator")),
    uiOutput("proj_status"), hr(),
    div(class = "small text-muted",
        "Converts a REDCap export into ELSO Registry import XML. ",
        "Research/governance tool \u2014 verify every file before upload.")),

  nav_panel("1 \u00b7 Project", icon = icon("folder-open"),
    layout_columns(col_widths = c(6, 6),
      card(card_header("Open or create a project"),
        textInput("proj_dir", "Project folder", placeholder = "e.g. D:/elso_jobs/StudyA", width = "100%"),
        textInput("proj_name", "Project name", value = "StudyA"),
        textInput("center_no", "ELSO Center No. (optional)", value = ""),
        div(actionButton("btn_create", "Create", class = "btn-primary"),
            actionButton("btn_open", "Open existing"))),
      card(card_header("Spec"),
        uiOutput("spec_info")))),

  nav_panel("2 \u00b7 Import REDCap", icon = icon("file-import"),
    card(card_header("Load a REDCap export"),
      radioButtons("src_type", NULL, c("ODM XML" = "odm", "CSV (+ data dictionary)" = "csv"), inline = TRUE),
      fileInput("odm_file", "REDCap ODM XML", accept = c(".xml"), width = "100%"),
      conditionalPanel("input.src_type == 'csv'",
        fileInput("csv_records", "Records CSV", accept = ".csv", width = "100%"),
        fileInput("csv_dict", "Data dictionary CSV (optional)", accept = ".csv", width = "100%")),
      div(actionButton("btn_sample", "Load bundled synthetic sample", class = "btn-outline-secondary btn-sm"),
          span(class = "small text-muted ms-2", "3 synthetic patients; no real data.")),
      textOutput("import_info")),
    layout_columns(col_widths = c(6, 6),
      card(card_header("Field dictionary"), DTOutput("dict_tbl")),
      card(card_header("Records (preview)"), DTOutput("rec_tbl")))),

  nav_panel("3 \u00b7 Map fields", icon = icon("diagram-project"),
    card(card_header("Grouping keys"),
      layout_columns(col_widths = c(3,3,3,3),
        uiOutput("ui_patient_key"), uiOutput("ui_patient_form"),
        uiOutput("ui_run_form"), uiOutput("ui_run_key")),
      div(class = "small text-muted",
          "How flat REDCap rows collapse into Patient \u2192 Run. Bind repeating instruments to ELSO collections below.")),
    card(card_header("Sub-collection bindings (run-level + addenda repeats)"),
      div(class = "small text-muted mb-2",
          "Bind each ELSO repeating list to a REDCap instrument. ",
          "Link field matches the parent's key (run key, or a parent list's key field). ",
          "Addenda lists are grouped below — leave a group untouched to omit it."),
      uiOutput("ui_subcoll")),
    card(card_header("Field mapping"),
      div(actionButton("btn_auto", "Auto-suggest mapping", class = "btn-primary"),
          downloadButton("dl_map", "Save template"),
          span(class = "ms-2", fileInput("up_map", NULL, accept = ".json", width = "260px", placeholder = "Load template"))),
      selectInput("map_section", "Section", SECTIONS, selected = "Patient", width = "400px"),
      uiOutput("map_editor"),
      actionButton("btn_apply_section", "Apply this section", class = "btn-secondary"))),

  nav_panel("4 \u00b7 Recode values", icon = icon("right-left"),
    card(card_header("Coded value crosswalks (REDCap \u2192 ELSO code)"),
      div(class = "small text-muted mb-2",
          "Auto-filled where REDCap choice labels match ELSO code-list labels. Review before export."),
      DTOutput("recode_tbl"))),

  nav_panel("5 \u00b7 De-identify", icon = icon("user-secret"),
    card(card_header("Optional de-identification (off by default)"),
      checkboxInput("deid_on", "Enable de-identification", FALSE),
      conditionalPanel("input.deid_on == true",
        uiOutput("ui_deid_cols"),
        numericInput("deid_shift", "Max date shift (days, 0 = none)", value = 0, min = 0, step = 1),
        textInput("deid_secret", "Project secret", value = "elso-project-secret"),
        div(class = "small text-muted",
            "Pseudonymizes chosen ID columns (stable tokens) and shifts dates per-patient. ",
            "Preserves intervals within a patient. The controller confirms adequacy.")))),

  nav_panel("6 \u00b7 Validate", icon = icon("clipboard-check"),
    card(card_header("Validate"),
      actionButton("btn_validate", "Generate & validate", class = "btn-primary"),
      uiOutput("valid_summary")),
    card(card_header("Issues"), DTOutput("issues_tbl"))),

  nav_panel("7 \u00b7 Generate XML", icon = icon("file-code"),
    card(card_header("ELSO import XML"),
      div(actionButton("btn_generate", "Generate", class = "btn-primary"),
          downloadButton("dl_xml", "Download .xml")),
      textOutput("gen_info"),
      tags$pre(style = "max-height:480px; overflow:auto;", textOutput("xml_preview"))))
)

# ---- server ----------------------------------------------------------------
server <- function(input, output, session) {
  rv <- reactiveValues(proj = NULL, parsed = NULL, map = list(), recode = list(),
                       datefmt = list(), binding = list(), doc = NULL, issues = NULL,
                       xsd = NULL, id_index = list())

  output$spec_info <- renderUI(tagList(
    div(tags$b("ELSO spec: "), CAT$catalogue$version),
    div(tags$b("Leaves: "), nrow(LEAVES),
        " | required: ", sum(LEAVES$required),
        " | coded: ", sum(LEAVES$has_codes)),
    div(class = "small text-muted", "Structure from the official XSD; codes/ranges from the lookups workbook.")))

  output$proj_status <- renderUI({
    if (is.null(rv$proj)) return(div(class = "text-muted", "No project open."))
    tagList(div(tags$b("Project: "), rv$proj$name),
            div(class = "small text-muted", input$proj_dir))
  })

  observeEvent(input$btn_create, {
    req(nzchar(input$proj_dir))
    tryCatch({ rv$proj <- el_project_create(input$proj_dir, input$proj_name, input$center_no)
      showNotification("Project created.", type = "message") },
      error = function(e) showNotification(conditionMessage(e), type = "error"))
  })
  observeEvent(input$btn_open, {
    req(nzchar(input$proj_dir))
    tryCatch({ rv$proj <- el_project_open(input$proj_dir)
      showNotification("Project opened.", type = "message") },
      error = function(e) showNotification(conditionMessage(e), type = "error"))
  })

  # ---- import ----
  observeEvent(list(input$odm_file, input$csv_records, input$csv_dict, input$src_type), {
    p <- tryCatch({
      if (input$src_type == "odm") { req(input$odm_file); el_read_redcap_odm(input$odm_file$datapath) }
      else { req(input$csv_records)
             el_read_redcap_csv(input$csv_records$datapath,
                                if (!is.null(input$csv_dict)) input$csv_dict$datapath else NULL) }
    }, error = function(e) { showNotification(conditionMessage(e), type = "error"); NULL })
    req(p); rv$parsed <- p
    rv$datefmt <- list(); rv$doc <- NULL
    if (!is.null(rv$proj)) el_log_append(rv$proj$dir %||% input$proj_dir, "import",
                                         list(fields = nrow(p$dictionary), records = nrow(p$records)))
  }, ignoreInit = TRUE)

  observeEvent(input$btn_sample, {
    sp <- file.path(dirname(getOption("el.app_dir")), "samples", "sample_redcap.odm.xml")
    p <- tryCatch(el_read_redcap_odm(sp), error = function(e) {
      showNotification(paste("Sample load failed:", conditionMessage(e)), type = "error"); NULL })
    req(p); rv$parsed <- p; rv$datefmt <- list(); rv$doc <- NULL
    showNotification("Loaded synthetic sample (3 patients).", type = "message")
  })

  output$import_info <- renderText({
    p <- rv$parsed; if (is.null(p)) return("No REDCap export loaded.")
    sprintf("%d fields | %d records | forms: %s", nrow(p$dictionary), nrow(p$records),
            paste(p$forms, collapse = ", "))
  })
  output$dict_tbl <- renderDT({ req(rv$parsed)
    datatable(rv$parsed$dictionary[, c("field","label","form","coded")],
              options = list(pageLength = 8, scrollX = TRUE), rownames = FALSE) })
  output$rec_tbl <- renderDT({ req(rv$parsed)
    datatable(head(rv$parsed$records, 100), options = list(pageLength = 6, scrollX = TRUE), rownames = FALSE) })

  # ---- grouping key selectors ----
  field_choices <- reactive({ req(rv$parsed)
    c(setNames(rv$parsed$dictionary$field, paste0(rv$parsed$dictionary$field, " \u2014 ", rv$parsed$dictionary$label))) })
  form_choices <- reactive({ req(rv$parsed); c("(none)" = "", rv$parsed$forms) })

  output$ui_patient_key <- renderUI({ req(rv$parsed)
    selectInput("patient_key", "Patient key", c(".subject", names(rv$parsed$records)),
                selected = ".subject", selectize = FALSE) })
  output$ui_patient_form <- renderUI(selectInput("patient_form", "Patient/hosp instrument",
                                                 form_choices(), selectize = FALSE))
  output$ui_run_form <- renderUI(selectInput("run_form", "Run instrument",
                                             form_choices(), selectize = FALSE))
  output$ui_run_key <- renderUI({ req(rv$parsed)
    selectInput("run_key", "Run key field", c("(none)" = "", field_choices()), selectize = FALSE) })

  # one binder row: instrument + link, plus a key field when it has nested children
  subcoll_binder <- function(pth) {
    nested   <- !identical(SUBCOLL_PARENT[[pth]], "")
    is_parent <- isTRUE(SUBCOLL_IS_PARENT[[pth]])
    link_lbl <- if (nested)
                  paste0("Link field (to ", basename(SUBCOLL_PARENT[[pth]]), " key)")
                else "Link field (to run key)"
    widths <- if (is_parent) c(3, 3, 3, 3) else c(4, 4, 4)
    controls <- list(
      div(class = if (nested) "ps-3 border-start" else NULL,
          tags$b(el_subcoll_label(pth)),
          if (nested) span(class = "badge bg-light text-dark ms-1", "nested"),
          tags$br(), span(class = "small text-muted", basename(pth))),
      selectInput(paste0("sub_form_", id_of(pth)), "REDCap instrument",
                  form_choices(), selectize = FALSE),
      selectInput(paste0("sub_link_", id_of(pth)), link_lbl,
                  c("(none)" = "", field_choices()), selectize = FALSE))
    if (is_parent)
      controls <- c(controls, list(
        selectInput(paste0("sub_key_", id_of(pth)), "Key field (for nested lists)",
                    c("(none)" = "", field_choices()), selectize = FALSE)))
    do.call(layout_columns, c(list(col_widths = widths), controls))
  }

  output$ui_subcoll <- renderUI({ req(rv$parsed)
    panels <- lapply(SUBCOLL_ORDER, function(grp) {
      pths <- SUBCOLL_PATHS[SUBCOLL_GROUP == grp]
      if (!length(pths)) return(NULL)
      # parents before their children so the layout reads top-down
      pths <- pths[order(nchar(pths))]
      accordion_panel(sprintf("%s (%d)", grp, length(pths)),
                      lapply(pths, subcoll_binder))
    })
    panels <- Filter(Negate(is.null), panels)
    # open the run-level block by default; addenda collapsed to reduce clutter
    n_run <- sum(SUBCOLL_GROUP == "Run-level collections")
    do.call(accordion, c(panels,
      list(open = sprintf("Run-level collections (%d)", n_run), multiple = TRUE)))
  })

  # ---- field mapping editor (per section) ----
  output$map_editor <- renderUI({
    req(rv$parsed)
    sec <- input$map_section %||% "Patient"
    lv <- LEAVES[LEAVES$section_label == sec, ]
    fc <- c("(unmapped)" = "", field_choices())
    idx <- list()
    rows <- lapply(seq_len(nrow(lv)), function(i) {
      pth <- lv$path[i]; iid <- id_of(pth); idx[[iid]] <<- pth
      cur <- rv$map[[pth]]$source %||% ""
      tag <- lv$name[i]
      badge <- paste0(if (lv$required[i]) "\u2605 " else "",
                      if (lv$has_codes[i]) "[coded] " else "",
                      if (lv$kind[i] %in% c("date","datetime")) "[date] " else "")
      layout_columns(col_widths = c(5, 7),
        div(tags$b(tag), tags$br(), span(class = "small text-muted", badge)),
        selectInput(iid, NULL, fc, selected = cur))
    })
    rv$id_index <- idx
    tagList(rows)
  })

  observeEvent(input$btn_apply_section, {
    for (iid in names(rv$id_index)) {
      pth <- rv$id_index[[iid]]; val <- input[[iid]]
      if (!is.null(val) && nzchar(val)) rv$map[[pth]] <- list(source = val)
      else rv$map[[pth]] <- NULL
    }
    rv$datefmt <- modifyList(el_default_datefmt(CAT, rv$map), rv$datefmt)
    rv$recode <- el_auto_recode(CAT, rv$parsed, rv$map)
    showNotification("Section mapping applied.", type = "message")
  })

  observeEvent(input$btn_auto, {
    req(rv$parsed)
    rv$map <- el_auto_suggest_map(CAT, rv$parsed$dictionary)
    rv$recode <- el_auto_recode(CAT, rv$parsed, rv$map)
    rv$datefmt <- el_default_datefmt(CAT, rv$map)
    showNotification(sprintf("Auto-mapped %d fields, %d recodes.", length(rv$map), length(rv$recode)), type = "message")
  })

  # ---- recode preview ----
  output$recode_tbl <- renderDT({
    if (!length(rv$recode)) return(datatable(data.frame(message = "No coded mappings yet \u2014 map coded fields then auto-suggest.")))
    rows <- do.call(rbind, lapply(names(rv$recode), function(pth) {
      v <- rv$recode[[pth]]
      data.frame(elso_field = basename(pth), redcap_value = names(v), elso_code = unname(v),
                 stringsAsFactors = FALSE)
    }))
    datatable(rows, options = list(pageLength = 12, scrollX = TRUE), rownames = FALSE)
  })

  output$ui_deid_cols <- renderUI({ req(rv$parsed)
    cols <- names(rv$parsed$records)
    tagList(
      selectInput("deid_ids", "Identifier columns to pseudonymize", cols, multiple = TRUE,
                  selected = intersect(c(".subject","patient_id","record_id"), cols)),
      selectInput("deid_dates", "Date columns to shift", cols, multiple = TRUE))
  })

  # ---- build binding + hierarchy ----
  build_binding <- function() {
    subs <- list()
    for (pth in SUBCOLL_PATHS) {
      f <- input[[paste0("sub_form_", id_of(pth))]] %||% ""
      if (nzchar(f)) subs[[pth]] <- list(
        form       = f,
        link_field = input[[paste0("sub_link_", id_of(pth))]] %||% "",
        key_field  = if (isTRUE(SUBCOLL_IS_PARENT[[pth]]))
                       input[[paste0("sub_key_", id_of(pth))]] %||% "" else "")
    }
    list(patient_key = input$patient_key %||% ".subject",
         patient_form = input$patient_form %||% "",
         run_form = input$run_form %||% "",
         run_key_field = input$run_key %||% "",
         subcollections = subs)
  }

  do_generate <- function() {
    req(rv$parsed)
    parsed <- rv$parsed
    if (isTRUE(input$deid_on)) {
      parsed$records <- el_apply_deident(parsed$records, list(
        secret = input$deid_secret, id_cols = input$deid_ids, date_cols = input$deid_dates,
        max_shift_days = input$deid_shift, patient_key = input$patient_key %||% ".subject"))
    }
    rv$binding <- build_binding()
    hier <- el_build_hierarchy(parsed, rv$binding)
    el_generate_xml(CAT, hier, rv$map, rv$recode, rv$datefmt)
  }

  # ---- validate ----
  observeEvent(input$btn_validate, {
    doc <- tryCatch(do_generate(), error = function(e) { showNotification(conditionMessage(e), type="error"); NULL })
    req(doc); rv$doc <- doc
    rv$xsd <- el_validate_xsd(doc, getOption("el.xsd_path"))
    rv$issues <- el_semantic_check(CAT, doc)
  })
  output$valid_summary <- renderUI({
    if (is.null(rv$xsd)) return(div(class = "text-muted", "Not validated yet."))
    s <- el_validation_summary(rv$issues)
    tagList(
      div(tags$b("XSD: "), if (isTRUE(rv$xsd$ok)) span(class="text-success","valid")
                            else span(class="text-danger", "INVALID")),
      div(tags$b("Semantic: "), sprintf("%d errors, %d warnings", s$n_error, s$n_warning)))
  })
  output$issues_tbl <- renderDT({
    if (is.null(rv$issues) || !nrow(rv$issues)) return(datatable(data.frame(message = "No issues (validate first).")))
    datatable(rv$issues, options = list(pageLength = 12, scrollX = TRUE), rownames = FALSE) |>
      formatStyle("severity", target = "row",
                  backgroundColor = styleEqual(c("error","warning"), c("#f8d7da","#fff3cd")))
  })

  # ---- generate ----
  observeEvent(input$btn_generate, {
    doc <- tryCatch(do_generate(), error = function(e) { showNotification(conditionMessage(e), type="error"); NULL })
    req(doc); rv$doc <- doc
    rv$xsd <- el_validate_xsd(doc, getOption("el.xsd_path"))
    if (!is.null(rv$proj)) {
      out <- file.path(el_project_paths(rv$proj$dir %||% input$proj_dir)$outputs, "elso_import.xml")
      el_write_xml(doc, out); el_manifest_write(rv$proj$dir %||% input$proj_dir)
      el_log_append(rv$proj$dir %||% input$proj_dir, "generate",
                    list(xsd_valid = rv$xsd$ok, output = basename(out)))
    }
    showNotification("XML generated.", type = "message")
  })
  output$gen_info <- renderText({
    if (is.null(rv$doc)) return("Not generated yet.")
    sprintf("Generated. XSD valid: %s. %d patient record(s).",
            rv$xsd$ok %||% NA, length(xml2::xml_find_all(rv$doc, "//*[local-name()='PatientXML']")))
  })
  output$xml_preview <- renderText({
    req(rv$doc)
    txt <- as.character(rv$doc); lines <- strsplit(txt, "\n")[[1]]
    paste(head(lines, 200), collapse = "\n")
  })

  output$dl_xml <- downloadHandler(
    filename = function() "elso_import.xml",
    content = function(file) { doc <- rv$doc %||% do_generate(); el_write_xml(doc, file) })

  output$dl_map <- downloadHandler(
    filename = function() "elso_mapping.json",
    content = function(file) el_save_mapping(list(binding = build_binding(), map = rv$map,
                                                  recode = rv$recode, datefmt = rv$datefmt), file))

  observeEvent(input$up_map, {
    req(input$up_map)
    tpl <- tryCatch(el_load_mapping(input$up_map$datapath), error = function(e) NULL)
    req(tpl)
    rv$map <- tpl$map %||% list(); rv$recode <- tpl$recode %||% list()
    rv$datefmt <- tpl$datefmt %||% list(); rv$binding <- tpl$binding %||% list()
    showNotification("Mapping template loaded.", type = "message")
  })
}

shinyApp(ui, server)
