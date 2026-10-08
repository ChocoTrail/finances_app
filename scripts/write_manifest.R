#!/usr/bin/env Rscript

runtime_files <- c(
  "app.R",
  file.path(
    "R",
    c(
      "app_server.R",
      "budget_config.R",
      "config.R",
      "configuration_service.R",
      "database.R",
      "database_queries.R",
      "import_service.R",
      "overview_service.R",
      "prototype_contracts.R",
      "transaction_pipeline.R",
      "transaction_service.R"
    )
  ),
  file.path("www", c("ui.css", "ui.js")),
  file.path(
    "www",
    "brand",
    c(
      "README.md",
      "fonts/AzeretMono-Variable.ttf",
      "fonts/Mina-Bold.ttf",
      "fonts/OFL-AzeretMono.txt",
      "fonts/OFL-Mina.txt",
      "fonts/OFL-Recursive.txt",
      "fonts/Recursive-Variable.ttf",
      "logo/favicon/favicon-16.png",
      "logo/favicon/favicon-32.png",
      "logo/favicon/favicon-48.png",
      "logo/favicon/favicon.svg",
      "logo/svg/choco-trail-lockup-horizontal-current-outlined.svg",
      "logo/svg/choco-trail-lockup-horizontal-ink-outlined.svg",
      "logo/svg/choco-trail-lockup-horizontal-paper-outlined.svg",
      "logo/svg/choco-trail-mark-current.svg",
      "logo/svg/choco-trail-mark-ink.svg",
      "logo/svg/choco-trail-mark-paper.svg",
      "logo/svg/choco-trail-wordmark-current-outlined.svg",
      "logo/svg/choco-trail-wordmark-ink-outlined.svg",
      "logo/svg/choco-trail-wordmark-paper-outlined.svg"
    )
  )
)

missing_files <- runtime_files[!file.exists(runtime_files)]

if (length(missing_files) > 0L) {
  stop(
    "Cannot write manifest; missing runtime files: ",
    paste(missing_files, collapse = ", "),
    call. = FALSE
  )
}

rv_status <- system2(
  "rv",
  c("export", "renv", "--output", "renv.lock")
)

if (!identical(rv_status, 0L)) {
  stop("Cannot write manifest; rv lockfile export failed.", call. = FALSE)
}

rsconnect::writeManifest(
  appDir = ".",
  appFiles = runtime_files,
  appPrimaryDoc = "app.R",
  appMode = "shiny",
  dependencyResolution = "strict"
)
