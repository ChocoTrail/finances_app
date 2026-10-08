test_that("server returns acknowledged JSON", {
  server <- create_finance_app_server(prototype_connection_factory)

  shiny::testServer(server, {
    session$setInputs(prototype_message = "Bridge is working")

    expect_true(output$prototype_echo$acknowledged)
    expect_equal(output$prototype_echo$message, "Bridge is working")
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
