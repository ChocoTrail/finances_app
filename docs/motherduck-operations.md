# MotherDuck operations

The finance application uses the `choco_trail` MotherDuck database and an
isolated `finances_app` schema. Local development remains the default and uses
the ignored `data/local/finances.duckdb` file.

## Secret setup

`MOTHERDUCK_TOKEN` is the only required secret. Copy `.Renviron.example` to
`.Renviron`, add the token locally without quotes, and never commit that file or
paste the value into logs, issues, or documentation.

The deployed application will also set the non-secret
`FINANCES_APP_DATABASE_TARGET=motherduck`. When unset, the application uses the
local database.

The connection temporarily exposes the secret through the lowercase variable
expected by the DuckDB extension, then restores the previous process
environment. The token is never written into SQL or application output.

## Preview initialization

From the project root, run:

```sh
Rscript scripts/06_initialize_motherduck.R
```

The preview connects to `choco_trail`, reports whether `finances_app` already
exists, and displays the planned aggregate counts. It does not create a schema
or write data.

Review that the preview targets:

- Database: `choco_trail`
- Schema: `finances_app`
- Transactions: 663 for the initial April–September 2026 history
- Reimbursable decisions: 21
- Merchant rules: 21
- Budget versions: 1
- Allocations: 5

## Confirm initialization

After reviewing the preview, explicitly write with:

```sh
Rscript scripts/06_initialize_motherduck.R --write
```

The write path creates and selects the schema, applies pending versioned
migrations, seeds the initial history in a transaction, and independently
compares the resulting transaction decisions, merchant rules, category
spending, and rollover ledger with the protected local pipeline.

If the schema already contains data, the script does not seed it again. It
validates the existing contents and fails if they differ from the protected
baseline.

## Recovery

- A connection failure does not change the local database. Confirm that the
  token is present and current without sharing its value.
- A migration failure rolls back that migration. Correct the error and rerun
  the initializer.
- A seed failure rolls back the complete initial seed. It never commits only a
  subset of the finance history.
- Do not delete or reset the production schema as routine troubleshooting.
