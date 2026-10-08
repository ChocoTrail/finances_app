test_that("empty preview contract is explicit and safe", {
  contract <- empty_import_preview_contract()

  expect_equal(contract$status, "waiting")
  expect_false(contract$can_confirm)
  expect_equal(contract$problems, list())
  expect_match(contract$complete_day_notice, "complete calendar-day")
})

test_that("preview contract exposes aggregates without transaction descriptions", {
  connection <- prototype_connection_factory()
  on.exit(disconnect_finance_database(connection), add = TRUE)
  file_path <- write_prototype_export(tibble::tibble(
    DATE = "10/01/2026",
    DESCRIPTION = "PRIVATE DESCRIPTION",
    AMOUNT = "-25.00",
    `CHECK #` = NA_character_,
    STATUS = "Posted"
  ))
  on.exit(unlink(file_path), add = TRUE)

  preview <- preview_transaction_import(
    connection,
    file_path,
    "credit_card_jacob"
  )
  contract <- format_import_preview_contract(preview)

  expect_equal(contract$status, "ready")
  expect_equal(contract$posted_row_count, 1L)
  expect_equal(contract$new_transaction_count, 1L)
  expect_false(grepl("PRIVATE DESCRIPTION", jsonlite::toJSON(contract)))
})
