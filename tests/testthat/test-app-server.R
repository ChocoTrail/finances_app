test_that("server returns acknowledged JSON", {
  server <- create_finance_app_server(prototype_connection_factory)

  shiny::testServer(server, {
    session$setInputs(prototype_message = "Bridge is working")

    expect_true(output$prototype_echo$acknowledged)
    expect_equal(output$prototype_echo$message, "Bridge is working")
  })
})

test_that("server returns the selected Overview slice", {
  server <- create_finance_app_server(overview_connection_factory)

  shiny::testServer(server, {
    session$setInputs(
      overview_month = "2026-04-01",
      overview_category = "personal_discretionary"
    )

    expect_equal(output$overview_screen$selected_month, "2026-04-01")
    expect_equal(
      output$overview_screen$selected_category$category_code,
      "personal_discretionary"
    )
    expect_equal(output$overview_screen$transaction_count, 1L)
    expect_equal(
      output$overview_screen$transactions[[1]]$description,
      "TARGET STORE"
    )
  })
})

test_that("server saves and refreshes a pending transaction decision", {
  server <- create_finance_app_server(transaction_maintenance_connection_factory)

  shiny::testServer(server, {
    session$setInputs(transaction_filters = list(
      start_date = NULL,
      end_date = NULL,
      review_state = "pending"
    ))
    transaction <- output$transaction_screen$transactions[[1]]

    expect_equal(output$transaction_screen$total_count, 1L)

    session$setInputs(transaction_save_request = list(
      request_id = "server-save-request",
      transaction_id = transaction$transaction_id,
      category_code = "food_living",
      is_reimbursable = FALSE,
      is_excluded = FALSE,
      note = "Reviewed in server test"
    ))

    expect_equal(output$transaction_save_result$status, "saved")
    expect_equal(output$transaction_screen$pending_review_count, 0L)
    expect_equal(output$transaction_screen$total_count, 0L)
  })
})

test_that("server saves configuration and refreshes affected screens", {
  server <- create_finance_app_server(transaction_maintenance_connection_factory)

  shiny::testServer(server, {
    merchant_count_before <- length(output$configuration_screen$merchants)
    session$setInputs(transaction_filters = list(
      start_date = NULL,
      end_date = NULL,
      search = "NEW MERCHANT"
    ))

    session$setInputs(configuration_save_request = list(
      kind = "merchant",
      request_id = "server-merchant-save",
      rule_id = NULL,
      display_name = "New merchant",
      description_pattern = "^NEW MERCHANT$",
      category_code = "food_living",
      effective_date = "2026-05-01",
      is_active = TRUE,
      apply_existing = TRUE
    ))

    expect_equal(output$configuration_save_result$status, "saved")
    expect_equal(length(output$configuration_screen$merchants), merchant_count_before + 1L)
    expect_equal(output$transaction_screen$transactions[[1]]$category_code, "food_living")
    expect_equal(output$transaction_screen$transactions[[1]]$merchant, "New merchant")
  })
})

test_that("server previews an uploaded CSV without writing it", {
  file_path <- write_prototype_export(tibble::tibble(
    DATE = c("10/01/2026", "10/02/2026"),
    DESCRIPTION = c("TARGET STORE", "NEW SHOP"),
    AMOUNT = c("-25.00", "-10.00"),
    `CHECK #` = c(NA_character_, NA_character_),
    STATUS = c("Posted", "Posted")
  ))
  on.exit(unlink(file_path), add = TRUE)
  server <- create_finance_app_server(prototype_connection_factory)

  shiny::testServer(server, {
    session$setInputs(
      account_slot = "credit_card_jacob",
      account_file = list(
        name = "CreditCardJacob.csv",
        size = file.info(file_path)$size,
        type = "text/csv",
        datapath = file_path
      )
    )

    expect_equal(output$import_preview$status, "ready")
    expect_equal(output$import_preview$posted_row_count, 2L)
    expect_equal(output$import_preview$new_transaction_count, 2L)
    expect_match(output$import_preview$account_slot_notice, "credit_card_jacob")
  })
})

test_that("server returns every malformed-row problem", {
  file_path <- write_prototype_export(tibble::tibble(
    DATE = c("bad-date", "10/02/2026"),
    DESCRIPTION = c("TARGET STORE", "NEW SHOP"),
    AMOUNT = c("-25.00", "bad-amount"),
    `CHECK #` = c(NA_character_, NA_character_),
    STATUS = c("Posted", "Posted")
  ))
  on.exit(unlink(file_path), add = TRUE)
  server <- create_finance_app_server(prototype_connection_factory)

  shiny::testServer(server, {
    suppressWarnings(
      session$setInputs(
        account_slot = "credit_card_kendra",
        account_file = list(
          name = "CreditCardKendra.csv",
          size = file.info(file_path)$size,
          type = "text/csv",
          datapath = file_path
        )
      )
    )

    expect_equal(output$import_preview$status, "invalid")
    expect_setequal(
      vapply(output$import_preview$problems, `[[`, character(1), "code"),
      c("invalid_date", "invalid_amount")
    )
  })
})
