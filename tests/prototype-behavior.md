# ShinyReact application behavior

## Read-only Overview

- Overview is the default application view.
- The selected month defaults to the current calendar month.
- Month navigation stops at the configured budget start and current month.
- Exactly five category cards show available rollover, monthly spending, and allocation.
- A negative available balance is labeled as a deficit, not identified by color alone.
- Account freshness reports the latest successful coverage date for every supported account.
- Selecting a category opens a read-only transaction list filtered to that category and month.
- The filtered list distinguishes spending, refunds, and category offsets.
- The screen contract is purpose-built and does not expose database tables directly.

## Transaction maintenance

- Transactions can be filtered by date range, account, category, merchant rule, budget treatment, review state, and text search.
- The pending-review queue includes only transactions whose saved review state is pending.
- Selecting a category from Overview opens Transactions with that month and category already applied.
- Desktop uses compact rows; narrow screens use transaction cards without horizontal page scrolling.
- A three-dot action expands a transaction-specific editor.
- A saved edit can change category, reimbursable status, excluded status, and note.
- Saving confirms the transaction, records a transaction override, and writes one audit row atomically.
- A failed edit changes neither the saved decision nor its audit history.
- Repeating the same save request is idempotent.
- Merchant-default creation and management remain deferred to configuration work.

## Upload prototype

- The page identifies itself as a technical prototype for Family finances.
- React owns the account-slot selector and sends its value to the R server.
- The upload control is a genuine Shiny file input hosted inside React.
- Before a file is selected, the import-preview JSON reports `waiting`.
- Selecting a valid export returns coverage and aggregate new/known counts.
- Selecting a malformed export returns the complete blocking problem list.
- Previewing a file never writes an import or transaction.
- The preview reminds the user to verify the account slot and use complete-day exports.
- Text entered in the bridge check returns from R as acknowledged JSON.
- Output recalculation keeps the previous preview visible with reduced emphasis.
