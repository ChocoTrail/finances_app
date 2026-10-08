create_finance_app_server <- function(
  connection_factory = function() connect_app_finance_database()
) {
  force(connection_factory)

  function(input, output, session) {
    connection <- NULL
    connection_revision <- shiny::reactiveVal(0L)
    connection_error <- shiny::reactiveVal(NULL)
    data_revision <- shiny::reactiveVal(0L)
    transaction_save_result <- shiny::reactiveVal(list(status = "idle"))
    configuration_save_result <- shiny::reactiveVal(list(status = "idle"))
    import_preview_state <- shiny::reactiveVal(NULL)
    import_save_result <- shiny::reactiveVal(list(status = "idle"))

    connect_to_database <- function() {
      if (!is.null(connection) && DBI::dbIsValid(connection)) {
        disconnect_finance_database(connection)
      }

      tryCatch(
        {
          connection <<- connection_factory()
          connection_error(NULL)
        },
        error = function(error) {
          connection <<- NULL
          connection_error(conditionMessage(error))
        }
      )
      connection_revision(shiny::isolate(connection_revision()) + 1L)
    }

    require_connection <- function() {
      connection_revision()
      error_message <- connection_error()

      if (!is.null(error_message)) {
        stop(error_message, call. = FALSE)
      }
      if (is.null(connection) || !DBI::dbIsValid(connection)) {
        stop("The finance database connection is not available.", call. = FALSE)
      }

      connection
    }

    connect_to_database()
    session$onSessionEnded(function() {
      disconnect_finance_database(connection)
    })

    output$connection_status <- shinyreact::reactive_output({
      connection_revision()
      error_message <- connection_error()

      if (is.null(error_message)) {
        list(status = "ready")
      } else {
        list(
          status = "error",
          message = paste0(
            "The finance database is unavailable. ",
            "Check the connection and try again."
          )
        )
      }
    })

    shiny::observeEvent(
      input$connection_retry_request,
      {
        connect_to_database()
        if (is.null(connection_error())) {
          data_revision(data_revision() + 1L)
        }
      },
      ignoreInit = TRUE
    )

    output$upload_widget <- shiny::renderUI({
      shiny::fileInput(
        inputId = "account_file",
        label = "Account export",
        multiple = FALSE,
        accept = c(".csv", "text/csv"),
        buttonLabel = "Choose CSV",
        placeholder = "No file selected"
      )
    })
    shiny::outputOptions(
      output,
      "upload_widget",
      suspendWhenHidden = FALSE
    )

    output$overview_screen <- shinyreact::reactive_output({
      data_revision()
      build_overview_screen_contract(
        connection = require_connection(),
        selected_month = input$overview_month,
        selected_category = input$overview_category
      )
    })

    output$transaction_screen <- shinyreact::reactive_output({
      data_revision()
      build_transaction_screen_contract(
        connection = require_connection(),
        filters = input$transaction_filters
      )
    })

    output$transaction_save_result <- shinyreact::reactive_output({
      transaction_save_result()
    })

    output$configuration_screen <- shinyreact::reactive_output({
      data_revision()
      build_configuration_screen_contract(require_connection())
    })

    output$configuration_save_result <- shinyreact::reactive_output({
      configuration_save_result()
    })

    output$import_save_result <- shinyreact::reactive_output({
      import_save_result()
    })

    shiny::observeEvent(
      input$transaction_save_request,
      {
        request <- input$transaction_save_request
        request_id <- if (
          is.list(request) && "request_id" %in% names(request)
        ) {
          as.character(request$request_id)
        } else {
          NULL
        }

        result <- tryCatch(
          {
            saved <- save_transaction_decision(require_connection(), request)

            if (saved$status == "saved") {
              data_revision(data_revision() + 1L)
            }

            saved
          },
          error = function(error) {
            list(
              status = "error",
              request_id = request_id,
              message = conditionMessage(error)
            )
          }
        )

        transaction_save_result(result)
      },
      ignoreInit = TRUE
    )

    shiny::observeEvent(
      input$configuration_save_request,
      {
        request <- input$configuration_save_request
        request_id <- if (is.list(request) && "request_id" %in% names(request)) {
          as.character(request$request_id)
        } else {
          NULL
        }

        result <- tryCatch(
          {
            saved <- save_configuration_change(require_connection(), request)
            if (saved$status == "saved") data_revision(data_revision() + 1L)
            saved
          },
          error = function(error) {
            list(status = "error", request_id = request_id, message = conditionMessage(error))
          }
        )
        configuration_save_result(result)
      },
      ignoreInit = TRUE
    )

    output$import_preview <- shinyreact::reactive_output({
      upload <- input$account_file
      account <- input$account_slot

      if (is.null(upload) || is.null(account)) {
        import_preview_state(NULL)
        return(empty_import_preview_contract())
      }

      tryCatch(
        {
          preview <- preview_transaction_import(
            connection = require_connection(),
            file_path = upload$datapath[[1]],
            account = account,
            source_filename = upload$name[[1]]
          )
          import_preview_state(preview)
          format_import_preview_contract(preview)
        },
        error = function(error) {
          import_preview_state(NULL)
          format_import_preview_error(conditionMessage(error))
        }
      )
    })

    shiny::observeEvent(
      input$import_confirm_request,
      {
        request_id <- if (
          is.list(input$import_confirm_request) &&
            "request_id" %in% names(input$import_confirm_request)
        ) {
          as.character(input$import_confirm_request$request_id)
        } else {
          NULL
        }

        result <- tryCatch(
          {
            request <- normalize_import_confirmation_request(
              input$import_confirm_request
            )
            preview <- import_preview_state()

            if (is.null(preview)) {
              stop(
                "Preview the selected account export before confirming it.",
                call. = FALSE
              )
            }

            saved <- confirm_transaction_import(
              connection = require_connection(),
              preview = preview,
              confirmed_account = request$confirmed_account,
              confirmed_filename = request$confirmed_filename,
              confirmation_id = request$request_id
            )
            if (saved$status == "saved") {
              data_revision(data_revision() + 1L)
            }

            c(list(request_id = request$request_id), saved)
          },
          error = function(error) {
            list(
              status = "error",
              request_id = request_id,
              message = conditionMessage(error)
            )
          }
        )

        import_save_result(result)
      },
      ignoreInit = TRUE
    )
  }
}
