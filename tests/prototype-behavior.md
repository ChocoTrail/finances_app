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

## Configuration administration

- Admin keeps upload preview, merchant defaults, monthly budgets, and budget setup in one place.
- Merchant defaults are searchable and expandable and can be created, edited, or deactivated, but never deleted.
- Merchant changes affect future imports unless the user deliberately chooses to apply an active rule to matching existing transactions.
- Every merchant save is server-validated, atomic, audited, and idempotent.
- Monthly budget changes create immutable versions effective in the current or a future month; earlier months are never rewritten.
- Every monthly budget version contains all five fixed categories and allocations sum exactly to its total.
- Budget start month and all five opening balances are configured together and saved atomically with an audit trail.
- Configuration saves refresh affected Overview, Transactions, and Admin data without reloading the application.

## Visual and interaction system

- The checked-in Choco Trail colors, Recursive interface type, Azeret Mono numeric type, compact spacing, and measured corner radii apply consistently across every view.
- Keyboard users can skip repeated navigation and every interactive control has a visible Current-and-Paper focus treatment.
- Interactive targets are at least 44 pixels tall, with distinct hover, pressed, selected, disabled, loading, success, warning, and error states.
- Semantic colors retain their defined meaning, and deficits, credits, review states, and failures also include a text or structural cue.
- Phone layouts avoid page-level horizontal scrolling; navigation and forms reflow rather than clip.
- Reduced-motion preferences remove nonessential interface transitions.

## Production connection

- A database connection failure leaves the application shell available with a clear, nontechnical error.
- The user can retry the MotherDuck connection in place without reloading the browser.
- A successful retry restores the normal screens and never creates an offline cache or alternate source of truth.

## Import workflow

- React owns the account-slot selector, while the upload control remains a genuine Shiny file input hosted inside React.
- Before a file is selected, the import-preview JSON reports `waiting`.
- Selecting a valid export returns coverage and aggregate new/known counts without writing anything.
- Selecting a malformed export returns every blocking problem and never offers confirmation.
- Confirmation repeats the selected account, filename, coverage, and transaction count.
- The user must explicitly verify the account slot and complete-day coverage before confirming.
- A confirmed import atomically saves its metadata, new transactions and decisions, audit rows, and sightings.
- Repeating the same confirmation request is idempotent, and a failed confirmation writes nothing.
- A successful import refreshes Overview, Transactions, Review, and Admin and displays a concise confirmation.
- Output recalculation keeps the previous preview visible with reduced emphasis.
