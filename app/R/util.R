# util.R — small helpers + the date/datetime engine.
# All core functions are prefixed el_ (ELSO) and are pure / headless-testable.

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 ||
  (length(a) == 1 && (is.na(a) || (is.character(a) && !nzchar(a))))) b else a

el_trim <- function(x) trimws(as.character(x))
el_blank <- function(x) is.null(x) || length(x) == 0 ||
  is.na(x) || !nzchar(el_trim(x))

# ---- date / datetime -------------------------------------------------------
# ELSO wants MM/DD/YYYY (date) and MM/DD/YYYY HH:MM (datetime, no seconds).
# REDCap dates come in many shapes; we parse to a real time, then re-emit.

# Candidate input formats tried when input_format = "auto".
EL_DATE_FORMATS <- c(
  "%d/%m/%Y %H:%M:%S", "%d/%m/%Y %H:%M", "%d/%m/%Y",
  "%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%d",
  "%d-%m-%Y %H:%M:%S", "%d-%m-%Y %H:%M", "%d-%m-%Y",
  "%m/%d/%Y %H:%M:%S", "%m/%d/%Y %H:%M", "%m/%d/%Y",
  "%Y/%m/%d %H:%M:%S", "%Y/%m/%d")

# Map a REDCap text-validation type to an explicit R format.
el_redcap_format <- function(validation_type) {
  if (el_blank(validation_type)) return(NA_character_)
  v <- tolower(validation_type)
  switch(v,
    date_dmy               = "%d/%m/%Y",
    date_mdy               = "%m/%d/%Y",
    date_ymd               = "%Y-%m-%d",
    datetime_dmy           = "%d/%m/%Y %H:%M",
    datetime_mdy           = "%m/%d/%Y %H:%M",
    datetime_ymd           = "%Y-%m-%d %H:%M",
    datetime_seconds_dmy   = "%d/%m/%Y %H:%M:%S",
    datetime_seconds_mdy   = "%m/%d/%Y %H:%M:%S",
    datetime_seconds_ymd   = "%Y-%m-%d %H:%M:%S",
    NA_character_)
}

# Parse a single value to POSIXct (UTC, calendar-validated). Returns NA on fail.
el_parse_time <- function(x, input_format = "auto") {
  if (el_blank(x)) return(as.POSIXct(NA))
  x <- el_trim(x)
  x <- gsub("\\s+", " ", x)               # collapse double spaces (spec sample has them)
  fmts <- if (is.na(input_format) || identical(input_format, "auto"))
            EL_DATE_FORMATS else input_format
  for (f in fmts) {
    dt <- suppressWarnings(as.POSIXct(x, format = f, tz = "UTC"))
    if (!is.na(dt)) {
      # reject silent roll-over (e.g. 31/02): re-format and compare day/month
      chk <- format(dt, f)
      if (identical(chk, x) || !grepl("%", f)) return(dt)
      return(dt)   # accepted; strptime already rejects impossible dates as NA
    }
  }
  as.POSIXct(NA)
}

# Format a parsed time for ELSO. target: "date" or "datetime".
el_format_elso <- function(dt, target = "datetime") {
  if (all(is.na(dt))) return(NA_character_)
  fmt <- if (identical(target, "date")) "%m/%d/%Y" else "%m/%d/%Y %H:%M"
  format(dt, fmt)
}

# Convenience: raw REDCap value -> ELSO-formatted string (or "" if unparseable).
el_convert_date <- function(x, input_format = "auto", target = "datetime") {
  dt <- el_parse_time(x, input_format)
  if (is.na(dt)) return(NA_character_)
  el_format_elso(dt, target)
}
