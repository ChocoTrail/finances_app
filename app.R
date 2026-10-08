source(file.path("R", "config.R"))
source(file.path("R", "transaction_pipeline.R"))
source(file.path("R", "budget_config.R"))
source(file.path("R", "database.R"))
source(file.path("R", "database_queries.R"))
source(file.path("R", "import_service.R"))
source(file.path("R", "prototype_contracts.R"))
source(file.path("R", "overview_service.R"))
source(file.path("R", "app_server.R"))

ui <- shinyreact::page_react(title = "Family finances")
server <- create_finance_app_server()

shiny::shinyApp(ui, server)
