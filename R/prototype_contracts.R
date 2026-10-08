empty_import_preview_contract <- function() {
  list(
    status = "waiting",
    account = NULL,
    source_filename = NULL,
    coverage_start = NULL,
    coverage_end = NULL,
    source_row_count = 0L,
    posted_row_count = 0L,
    new_transaction_count = 0L,
    known_transaction_count = 0L,
    duplicate_group_count = 0L,
    can_confirm = FALSE,
    problems = list(),
    account_slot_notice = NULL,
    complete_day_notice = paste0(
      "Only complete calendar-day exports are supported. ",
      "Do not confirm a partial-day export."
    )
  )
}

format_import_problems <- function(problems) {
  if (nrow(problems) == 0) {
    return(list())
  }

  purrr::pmap(
    problems,
    function(code, severity, source_row_number, message) {
      list(
        code = code,
        severity = severity,
        source_row_number = if (is.na(source_row_number)) NULL else source_row_number,
        message = message
      )
    }
  )
}

format_import_preview_contract <- function(preview) {
  if (is.null(preview)) {
    return(empty_import_preview_contract())
  }

  confirmation <- import_confirmation_details(preview)

  list(
    status = if (preview$can_confirm) "ready" else "invalid",
    account = preview$account,
    source_filename = preview$source_filename,
    coverage_start = if (is.na(preview$coverage_start)) NULL else as.character(preview$coverage_start),
    coverage_end = if (is.na(preview$coverage_end)) NULL else as.character(preview$coverage_end),
    source_row_count = preview$source_row_count,
    posted_row_count = preview$posted_row_count,
    new_transaction_count = preview$new_transaction_count,
    known_transaction_count = preview$known_transaction_count,
    duplicate_group_count = preview$duplicate_group_count,
    can_confirm = preview$can_confirm,
    problems = format_import_problems(preview$problems),
    account_slot_notice = confirmation$account_slot_notice[[1]],
    complete_day_notice = confirmation$complete_day_notice[[1]]
  )
}

format_import_preview_error <- function(message) {
  contract <- empty_import_preview_contract()
  contract$status <- "error"
  contract$message <- message
  contract
}
