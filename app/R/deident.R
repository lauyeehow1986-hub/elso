# deident.R — OPTIONAL de-identification, applied to the REDCap records BEFORE
# grouping/generation. Off by default. Two independent transforms:
#   * pseudonymize:  replace identifier columns with stable HMAC-derived tokens
#                    (same input -> same token, within a project secret)
#   * date shift:    shift chosen date columns by a per-patient integer number of
#                    days (deterministic from the patient id + secret), written
#                    back as ISO so downstream auto-parsing still works. Preserves
#                    intervals within a patient; breaks absolute dates.
#
# This is format-preserving de-id for research release; the data controller
# remains responsible for confirming adequacy. Not for defeating re-id on its own.

suppressPackageStartupMessages(library(openssl))

el_hmac_int <- function(key, secret) {
  h <- openssl::sha256(charToRaw(paste0(secret, "|", key)))
  strtoi(substr(as.character(h), 1, 7), 16L)      # 28-bit non-negative int
}

el_pseudonym <- function(key, secret, prefix = "ELSO") {
  h <- as.character(openssl::sha256(charToRaw(paste0(secret, "|id|", key))))
  paste0(prefix, toupper(substr(h, 1, 14)))       # 4 + 14 = 18 chars (10-20 ok)
}

el_apply_deident <- function(records, opts = list()) {
  secret   <- opts$secret %||% "elso-project-secret"
  id_cols  <- intersect(opts$id_cols %||% character(0), names(records))
  dt_cols  <- intersect(opts$date_cols %||% character(0), names(records))
  max_shift<- as.integer(opts$max_shift_days %||% 0L)
  pkey     <- opts$patient_key %||% ".subject"
  if (!pkey %in% names(records)) pkey <- ".subject"

  # pseudonymize id columns (stable per distinct value)
  for (col in id_cols) {
    vals <- records[[col]]; uniq <- unique(vals[!is.na(vals)])
    tok <- setNames(vapply(uniq, el_pseudonym, character(1), secret = secret), uniq)
    records[[col]] <- ifelse(is.na(vals), vals, tok[vals])
  }
  # per-patient date shift
  if (max_shift > 0L && length(dt_cols)) {
    pids <- records[[pkey]]
    shift <- vapply(pids, function(p) {
      if (is.na(p)) return(0L)
      (el_hmac_int(p, secret) %% (2L * max_shift + 1L)) - max_shift
    }, integer(1))
    for (col in dt_cols) {
      dt <- el_parse_time(records[[col]], "auto")
      shifted <- dt + as.difftime(shift, units = "days")
      out <- format(shifted, "%Y-%m-%d %H:%M:%S")
      out[is.na(shifted)] <- records[[col]][is.na(shifted)]  # keep unparseable as-is
      records[[col]] <- out
    }
  }
  records
}
