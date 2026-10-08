# Family finances app

This project is a private family budgeting application built with R and Shiny. It imports posted transactions from one checking account and two credit cards, applies family-specific classification rules, and compares net spending with monthly rollover allocations.

Real account exports belong in `data/raw/`. CSV files in that directory are ignored by Git and must never be committed.

## Current status

The repository currently contains the validated local transaction pipeline and
its protected April through September 2026 baseline. The database, import
service, ShinyReact interface, and deployment configuration described in
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

Private transaction overrides belong in `data/private/`. Files in that
directory are ignored by Git and will eventually be replaced by durable MotherDuck table(s).

The exploratory work remains in `scripts/01_explore_transactions.R`.

See [`docs/budget-rules.md`](docs/budget-rules.md) for the current budget, category definitions, and transaction treatment rules.
