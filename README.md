# Family finances app

This project is a private family budgeting application built with R and Shiny. It imports posted transactions from one checking account and two credit cards, applies family-specific classification rules, and compares net spending with monthly rollover allocations.

Real account exports belong in `data/raw/`. CSV files in that directory are ignored by Git and must never be committed.

## Current workflow

1. Place the three account exports in `data/raw/`.
2. Run `scripts/02_build_transactions.R` from the project root.
3. Confirm the account-level transaction counts before continuing.

Private transaction overrides belong in `data/private/`. Files in that
directory are ignored by Git and will eventually be replaced by durable MotherDuck table(s).

The exploratory work remains in `scripts/01_explore_transactions.R`.

See [`docs/budget-rules.md`](docs/budget-rules.md) for the current budget, category definitions, and transaction treatment rules.
