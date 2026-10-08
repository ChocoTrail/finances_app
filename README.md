# Family finances app

This project is a private family budgeting application built with R and Shiny. It imports posted transactions from one checking account and two credit cards, applies family-specific classification rules, and compares net spending with monthly rollover allocations.

Real account exports belong in `data/raw/`. CSV files in that directory are ignored by Git and must never be committed.

## Current status

The repository contains the validated local transaction pipeline, its
protected April through September 2026 baseline, and the versioned local
DuckDB schema, initial seed, and database-equivalence checks from implementation
steps 1 through 3. The `choco_trail.finances_app` MotherDuck schema is
initialized with the same validated history, completing step 4. The
preview-first atomic import service is implemented for step 5. The ShinyReact
interface and deployment configuration described in
[`docs/application-design.md`](docs/application-design.md) have not yet been
implemented.

## Current workflow

1. Place the three account exports in `data/raw/`.
2. Run `scripts/02_build_transactions.R` from the project root.
3. Confirm the account-level transaction counts before continuing.

Run the protected baseline checks from the project root with:

```sh
Rscript tests/test-baseline.R
```

The synthetic checks always run. The private baseline comparison runs only
when all three ignored account exports and the ignored transaction override
file are available locally.

## Local database

Run the database checks from the project root with:

```sh
Rscript tests/test-database.R
```

Create the initial local database with:

```sh
Rscript scripts/04_initialize_database.R
```

The initializer applies pending files from `migrations/`, then seeds the fixed
categories, current transactions and decisions, merchant rules, April 2026
budget version, and zero opening balances. It refuses to overwrite a database
that already contains seed data. Local `.duckdb` files under `data/local/` are
ignored by Git.

Validate that the local database reproduces the protected transaction
decisions, merchant rules, category spending, and monthly rollover ledger with:

```sh
Rscript scripts/05_validate_database_equivalence.R
```

The corresponding regression checks, including effective-month budget versions
and category-specific opening balances, run with:

```sh
Rscript tests/test-database-equivalence.R
```

## MotherDuck

The production target is the `finances_app` schema inside the existing
`choco_trail` MotherDuck database. `MOTHERDUCK_TOKEN` is the only secret;
`FINANCES_APP_DATABASE_TARGET` selects `local` or `motherduck` and defaults to
`local`.

Copy `.Renviron.example` to an ignored `.Renviron`, add the token without
quotes, and run the read-only preview:

```sh
Rscript scripts/06_initialize_motherduck.R
```

Do not use `--write` until the preview target and aggregate counts have been
reviewed. The complete initialization, validation, and recovery procedure is in
[`docs/motherduck-operations.md`](docs/motherduck-operations.md).

The production schema has been initialized and independently validated against
the protected local pipeline. Re-running the preview is safe and reports the
persisted table counts without changing data.

## Import service

[`R/import_service.R`](R/import_service.R) provides the server-side preview and
confirmation workflow for checking, Jacob's credit card, and Kendra's credit
card. Preview performs no writes. It validates every source row, filters to
posted transactions, assigns durable duplicate identities, reports new and
known rows, applies saved database merchant rules prospectively, and blocks the
whole file when any row is malformed.

Confirmation verifies the account slot and filename, then saves the import,
new transactions, initial decisions, audit rows, and transaction sightings in
one database transaction. Reimports preserve saved decisions and record another
sighting without duplicating transactions. Partial-day exports remain
unsupported and are called out in the confirmation contract.

Run the import regression suite with:

```sh
Rscript tests/test-import-service.R
```

Private transaction overrides belong in `data/private/`. Files in that
directory are ignored by Git and will eventually be replaced by durable MotherDuck table(s).

The exploratory work remains in `scripts/01_explore_transactions.R`.

See [`docs/budget-rules.md`](docs/budget-rules.md) for the current budget, category definitions, and transaction treatment rules.
