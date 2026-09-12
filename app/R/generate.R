# generate.R — build ELSO import XML from a grouped hierarchy + a mapping.
#
# The generator walks the XSD-derived catalogue TREE in schema declaration
# order (which satisfies both xsd:sequence and xsd:all). Emission rules that
# keep the output valid against the lenient XSD even from a sparse mapping:
#   * leaf with a value            -> <Tag>value</Tag>
#   * required leaf, no value      -> <Tag/>            (empty allowed; string type)
#   * required non-repeating group -> always emitted (empty if it has no content)
#   * optional non-repeating group -> emitted only if it gained children
#   * repeating group with N rows  -> N instances
#   * required repeating, 0 rows   -> one empty instance (to satisfy minOccurs>=1)
#   * optional repeating, 0 rows   -> skipped
#
# A node only consumes a scope-collection when its path is a genuine REPEAT
# LEVEL (a key the grouping stage populates). Some ELSO list *wrappers*
# (e.g. CardiacCath/Diagnostics) are themselves maxOccurs="unbounded" but are
# not repeat levels — the real repeating row is the element inside them
# (Diagnostic). Such a wrapper is emitted once and passes its scope straight
# through, so the inner repeat level can consume its own collection.
#
# hierarchy: list of patient scopes, each
#   list(row=<named chr>, races=list(scope), hosps=list(
#         list(row=<named chr>, runs=list(
#           list(row=<named chr>, coll=list("<repeat_level path>"=list(scope)))))))
# where a "scope" everywhere is at least list(row=<named chr vector>).
#
# map:    named list  path -> list(source=<redcap field>|NULL, const=<value>|NULL)
# recode: named list  path -> named chr vector (redcap value -> ELSO code)
# datefmt:named list  path -> list(input=<R format|"auto">, target="date"|"datetime")

suppressPackageStartupMessages(library(xml2))

el_is_repeating <- function(maxO)
  identical(maxO, "unbounded") ||
  (!is.na(suppressWarnings(as.integer(maxO))) && as.integer(maxO) > 1L)

el_empty_scope <- function()
  list(row = setNames(character(0), character(0)),
       races = list(), hosps = list(), runs = list(), coll = list())

# child scopes for a repeating node, by its level kind
el_child_scopes <- function(kind, path, scope) {
  pick <- switch(kind,
    patient          = scope$patients,
    hospitalization  = scope$hosps,
    run              = scope$runs,
    race             = scope$races,
    subcollection    = scope$coll[[path]],
    NULL)
  pick %||% list()
}

el_resolve_leaf <- function(path, node, row, map, recode, datefmt, leaf_kind) {
  spec <- map[[path]]
  raw <- NULL
  if (!is.null(spec)) {
    if (!el_blank(spec$const))       raw <- spec$const
    else if (!el_blank(spec$source) && spec$source %in% names(row))
      raw <- row[[spec$source]]
  }
  if (el_blank(raw)) return(NA_character_)
  raw <- el_trim(raw)
  rc <- recode[[path]]
  if (!is.null(rc) && !is.na(rc[raw]) && nzchar(rc[raw])) raw <- unname(rc[raw])
  kind <- leaf_kind[[path]] %||% "string"
  if (kind %in% c("date", "datetime")) {
    df <- datefmt[[path]] %||% list()
    conv <- el_convert_date(raw, df$input %||% "auto", df$target %||% kind)
    return(conv)   # NA if unparseable -> omitted here, flagged by validate.R
  }
  raw
}

el_emit <- function(node, path, scope, parent, map, recode, datefmt, leaf_kind,
                    repeat_levels = character(0)) {
  required <- suppressWarnings(as.integer(node$minOccurs)) %||% 1L
  required <- !is.na(required) && required >= 1L

  if (isTRUE(node$is_leaf)) {
    val <- el_resolve_leaf(path, node, scope$row %||% character(0),
                           map, recode, datefmt, leaf_kind)
    if (!el_blank(val)) { ch <- xml_add_child(parent, node$name); xml_text(ch) <- val }
    else if (required)  { xml_add_child(parent, node$name) }
    return(invisible())
  }

  # complex node: repeat only if this path is a genuine repeat level, else it
  # is a (possibly maxOccurs>1) wrapper -> emit once, pass the scope through.
  if (el_is_repeating(node$maxOccurs) && path %in% repeat_levels) {
    kind  <- el_level_kind(path)
    rows  <- el_child_scopes(kind, path, scope)
    if (length(rows) == 0L && required) rows <- list(el_empty_scope())
    for (child_scope in rows) {
      inst <- xml_add_child(parent, node$name)
      for (ch in node$children)
        el_emit(ch, paste0(path, "/", ch$name), child_scope, inst,
                map, recode, datefmt, leaf_kind, repeat_levels)
    }
  } else {
    grp <- xml_add_child(parent, node$name)
    for (ch in node$children)
      el_emit(ch, paste0(path, "/", ch$name), scope, grp,
              map, recode, datefmt, leaf_kind, repeat_levels)
    if (length(xml_children(grp)) == 0L && !required) xml_remove(grp)
  }
}

el_generate_xml <- function(cat, hierarchy, map = list(), recode = list(),
                            datefmt = list()) {
  lv <- el_leaves(cat)
  leaf_kind <- setNames(lv$kind, lv$path)
  repeat_levels <- unique(lv$repeat_level)
  tree <- cat$catalogue$tree
  doc <- xml_new_root("PatientList", xmlns = "urn:run-schema")
  top <- list(patients = hierarchy)
  # tree children of PatientList (i.e. PatientXML) walked in order
  for (ch in tree$children)
    el_emit(ch, ch$name, top, doc, map, recode, datefmt, leaf_kind, repeat_levels)
  # Re-parse so every element is bound to the default namespace (urn:run-schema).
  # xml_add_child leaves children in no-namespace in-memory even though the
  # serialized form is correct; the round-trip normalizes it for xml_validate.
  read_xml(as.character(doc))
}

# validate a generated doc against the bundled XSD; returns list(ok, errors)
el_validate_xsd <- function(doc, xsd_path) {
  if (!file.exists(xsd_path))
    return(list(ok = NA, errors = paste("XSD not found:", xsd_path)))
  schema <- read_xml(xsd_path)
  res <- tryCatch(xml2::xml_validate(doc, schema),
                  error = function(e) structure(FALSE, errors = conditionMessage(e)))
  list(ok = isTRUE(as.logical(res)),
       errors = attr(res, "errors") %||% character(0))
}

el_write_xml <- function(doc, path) {
  write_xml(doc, path, options = "format", encoding = "UTF-8")
  path
}
