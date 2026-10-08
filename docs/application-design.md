# Family finances application design

## Status

This document records the agreed design for the first version of the family
finances application. It is an implementation guide, not a description of
completed functionality.

The application will be a private spending-review and rollover-budget tool. It
will be maintained by one family member and viewed by both family members. It
will not attempt to provide a complete personal-finance or net-worth system.

## Product goals

After the transaction data is updated, the application should make it easy to
understand:

- Where money went.
- How much is currently available in each rollover category.
- How current each account's imported data is.
- How current spending compares with the allocation.
- Which newly imported transactions need review.

Reviewing and understanding spending is the primary goal. Budget control is a
secondary goal. The interface should avoid presenting a simplistic binary
"on track" judgment when payment timing or incomplete account data could make
that judgment misleading.

## Scope

### Included

- One checking account.
- Two credit-card accounts.
- Posted transactions from CSV account exports.
- Five fixed budget categories in the first version.
- Monthly allocations and independent category rollover balances.
- Transaction categorization and saved transaction decisions.
- Reimbursements, exclusions, refunds, and category offsets.
- Reusable merchant defaults.
- Historical month review.
- Transaction search and filtering.
- Administrative file imports and budget configuration.

### Excluded from the first version

- Net worth.
- Investment tracking.
- Tax planning.
- Bank and credit-card account balances.
- Credit-card payment obligations.
- Bill payment or cash-flow scheduling.
- Spending outside the three supported accounts.
- Offline operation.

## Users and access

The application will be deployed to Posit Connect Cloud. Both family members
may use the Overview and Transactions areas. The maintaining family member will
also use the Admin area.

The first version will not implement separate application roles, an admin PIN,
or role-specific transaction controls. The Admin area is an organizational
boundary in the interface rather than a separate authorization system. Access
protection will be handled by the hosting platform.

## Budget model

### Categories

The first version has five fixed category names:

1. Housing & related expenses
2. Transportation
3. Food & living expenses
4. Personal & discretionary
5. Rainy day & irregular expenses

Only the allocations are editable initially. Category creation, deletion, and
renaming are outside the first version.

### Monthly allocation

The initial monthly total is $6,300. The total may later be changed in the
Admin area. The five category allocations must always sum exactly to the
effective monthly total before a budget version can be saved.

Every budget change has an effective month. Earlier months retain the budget
version that applied to them; budget changes never rewrite prior months. When
creating a new budget version, the effective month selector defaults to the
following month but permits a deliberate change to the current month.

### Budget start and opening balances

The initial budget period begins in April 2026 with a zero opening balance for
each category. The budget start month and category opening balances will be
configurable so this assumption can be revised later.

### Rollover calculation

For each category and month:

> Available balance = opening rollover + monthly allocation - net spending

Unused amounts accumulate. Overspending creates a negative balance that future
allocations must recover. Category balances remain independent; an overall
surplus must not obscure a deficit in one category.

Every month from the configured budget start through the current month receives
its allocation and participates in rollover, including a month with no imported
transactions.

Refunds and category offsets reduce net spending. Reimbursable and excluded
transactions have zero budget effect.

## Data sources and transaction identity

Each account is uploaded through its own clearly labeled file slot:

- Checking
- Jacob's credit card
- Kendra's credit card

The exports use the existing five-column schema:

- `DATE`
- `DESCRIPTION`
- `AMOUNT`
- `CHECK #`
- `STATUS`

Only posted transactions are imported.

The exports do not provide a bank transaction ID. The durable composite
identity is therefore:

- Account
- Date
- Description
- Amount
- Check number
- Duplicate sequence

The duplicate sequence distinguishes otherwise identical transactions. It does
not make changed descriptions or amounts automatically identifiable as
revisions of an earlier transaction.

Uploaded exports are expected to contain complete calendar days. Partial-day
exports are unsupported because they cannot reliably reconcile otherwise
identical transactions from the same account and date.

## Import workflow

### Supported behavior

- Any one account may be uploaded independently.
- One or more accounts may be selected during an update.
- Export date ranges may vary and overlap.
- A missing transaction in a later export never deletes stored history.
- Uploading an exact transaction again does not create a duplicate.
- A transaction that does not exactly match a stored identity is inserted as a
  new transaction; the application does not try to infer changed transactions.
- The most recently available data from every account is included in the
  budget calculations.
- Each account's most recent successful import date is shown unobtrusively in
  the application as its "last updated" date.

### Preview and confirmation

Selecting a file creates a preview without changing durable data. The server
validates:

- The expected columns.
- Date and amount parsing.
- Posted status.
- Duplicate identities within the file.
- Exact matches already stored.

The preview shows file coverage dates, posted transaction counts, new
transactions, already-known transactions, and problems requiring attention.
The user must confirm the import before anything is written. The confirmation
shows the selected account, filename, coverage dates, and transaction count and
asks the user to verify that the file was placed in the correct account slot.
The CSV does not contain enough information for the application to verify the
account automatically.

Any malformed row blocks the complete file. The application must never import
only the valid-looking subset of a malformed financial export.

### Upsert behavior

- Exact identity match: retain the existing transaction and record that it was
  seen again.
- No identity match: insert a new transaction.

Each confirmed file is saved atomically. If validation or a database operation
fails, none of that file is committed. Retrying the same file must be safe and
idempotent.

After a successful import, the application displays a brief confirmation,
refreshes the budget results, and places uncertain new transactions into the
review queue. Import metadata remains in the database but does not need a
dedicated history panel in the first version.

If MotherDuck is unavailable, the application displays a clear error and retry
option. It does not maintain an offline cache.

## Transaction classification and review

### Stable saved decisions

Each transaction's assigned category and budget treatment are saved. They are
not completely regenerated from the current merchant-rule list whenever the
application starts. Adding or changing a merchant rule must not silently
rewrite historical transactions.

Each transaction has one category and one budget treatment. Splitting a single
transaction across categories or treatments is outside the first version.

The rule precedence remains:

1. Exclusions and reimbursable designations
2. Transaction-specific decisions
3. Reusable merchant rules
4. Default to Personal & discretionary

### Merchant definitions

A merchant definition contains:

- Display name.
- A matching definition for source descriptions.
- Default budget category.
- Effective date.
- Active status.

Merchant definitions may be edited or deactivated but are not permanently
deleted. This preserves the explanation for earlier classifications.

Changing a merchant default applies to the selected transaction and future
imports by default. Historical transactions change only through a deliberate
"apply to existing transactions" action in the Admin area.

Variable merchants such as Amazon, Target, and Venmo can retain Personal &
discretionary as their normal default while individual transactions are
overridden. Transactions matched by an active merchant rule do not require
review, but they remain editable later in the Transactions view.

### Review queue

After import, only new and uncertain transactions appear in the active review
queue. Existing merchant rules provide suggested categories. Confident rule
matches do not require review. Refunds enter the queue when their category
cannot be determined confidently. A new expense without a merchant-rule match
uses Personal & discretionary as its provisional category and remains available
for review.

The queue is a filterable table that permits multiple edits before saving.
Expanding a transaction exposes actions to:

- Change its category.
- Mark or unmark it as reimbursable.
- Exclude or include it in the budget.
- Create or update a future merchant default.

The general Transactions view also provides a three-dot menu for later one-off
corrections.

Reimbursable is a whole-transaction designation. The first version does not
split partially reimbursed transactions or link an expense to one or more
reimbursement deposits. The user chooses whether the complete expense is
reimbursable.

## Durable storage

MotherDuck is the production source of truth. The application will retain a
raw representation of each standardized transaction but will not retain the
uploaded CSV file itself.

The planned logical tables are:

### Imports

Internal import metadata, including account, source filename, import time,
coverage dates, row counts, and outcome.

### Transactions

Original account, date, description, amount, and check number; standardized
values; duplicate sequence; composite identity; first-seen import; last-seen
import.

### Transaction decisions

Current category, assignment source, review state, reimbursable status,
excluded status, and any note required to explain the decision.

### Decision audit log

A history of transaction-decision, merchant-rule, and budget changes, including
when each change was made. The first version does not provide an undo action; a
correction is recorded as another edit.

### Merchant rules

Merchant display names, matching definitions, default categories, effective
dates, and active status.

### Budget versions and allocations

Effective month, total monthly budget, and the five allocations for each
version.

### Budget opening balances

The configured budget start and each category's opening balance.

R code contains the classification engine and database initialization
defaults. After initialization, MotherDuck is the active source for merchant
definitions, budget versions, and saved transaction decisions. Code defaults
must not act as a competing live configuration.

The first production initialization will include the existing April through
September 2026 history, current merchant rules, one-off transaction decisions,
and saved reimbursable-airfare decisions.

The first version intentionally uses a lightweight recovery model. Uploaded CSV
files are not retained by the application. If the database must be rebuilt, the
maintainer will download the exports again, rerun the import pipeline, and
re-enter any application-only changes that cannot be recovered.

## Application views

### Overview

The Overview defaults to the current month and permits navigation to earlier
months. It emphasizes the five individual category balances rather than a
single combined rollover balance.

Each category card prioritizes:

1. Available rollover balance
2. Current-month spending versus allocation

Selecting a category opens the Transactions view filtered to that category and
month. Account freshness appears near the update context without dominating
the page.

### Transactions

The Transactions view supports search and filters for:

- Month or date range
- Account
- Category
- Merchant
- Budget treatment

Desktop layouts use a table. Narrow screens use compact transaction cards that
show merchant, amount, date, and category, with remaining details and actions
revealed on tap.

Refunds and offsets should be visually distinguishable from spending.

### Admin

The Admin area contains:

- Account-file upload and import preview.
- New-transaction review.
- Expandable, searchable merchant-default management.
- Monthly budget total and category allocations.
- Effective-month selection.
- Budget start and opening-balance settings.

CSV upload and bulk import review are computer-first workflows. The Overview
and Transactions experiences must be mobile-friendly from the beginning.

## Visual design

Visual implementation follows the checked-in
[Choco Trail brand essentials](choco-trail-brand-essentials.md). The finance
application is an endorsed project: the application name remains primary, and
the Choco Trail mark or lockup appears quietly in an about surface, footer, or
other secondary location rather than acting as the product name.

The guide determines:

- Color and typography tokens.
- Spacing and responsive breakpoints.
- Component appearance.
- Deficit and warning treatments.
- Loading, empty, success, and error states.

Negative category balances use Cinder Red, which the style guide reserves for
genuinely negative values and errors. A deficit must also be identified with
text, an icon, or another non-color cue.

The approved fonts, logo SVGs, and favicons are copied into `www/brand/` so the
deployed application does not depend on the sibling `personal_brand` repository
or a third-party font service. The client loads Recursive for interface text,
Azeret Mono for financial and tabular values, and Mina Bold only for the Choco
Trail wordmark. Font license files remain beside the font files.

Finance-specific components such as category cards, transaction rows, import
previews, and review dialogs apply the guide's tokens and principles; the guide
is not a fixed component-layout library.

## Technical architecture

### Server

R is the business-logic language. The R/Shiny server owns:

- CSV parsing and validation.
- Transaction identity and classification.
- Budget calculations.
- MotherDuck reads and writes.
- Mutation validation.
- Screen-oriented JSON data returned to the client.

The browser must not be trusted to enforce financial rules or database
constraints.

### Client

The interface will use React with TypeScript/TSX. ShinyReact provides the
client/server bridge, and Vite builds the client into assets served by the
Shiny application.

The React client owns:

- Navigation.
- Responsive layouts.
- Category and transaction presentation.
- Filters, menus, dialogs, and form state.
- Loading, recalculating, success, and error presentation.

The client and server communicate through purpose-built screen contracts such
as Overview, Transactions, Merchant settings, and Import preview. Database
tables are not exposed directly to the browser.

### Build and deployment

The selected ShinyReact tier follows the Vite/TSX pattern used by the later
official examples:

- Source client code lives under `src/`.
- Vite creates `www/ui.js` and `www/ui.css`.
- Built assets are committed so Posit Connect Cloud does not need to execute a
  Node build during deployment.
- The application has an `app.R` entry point and an R dependency lock file.
- MotherDuck credentials are stored as deployment secrets and never committed.

The public repository contains application code and non-sensitive defaults
only. Raw exports, private overrides, database contents, and credentials must
remain outside Git.

The approved brand assets under `www/brand/` are non-sensitive application
dependencies and are committed with the application.

The official `shinyreact-build-app` agent skill should be installed and used
when implementation begins. The `shinyreact-convert-app` skill is not needed
because there is no existing traditional Shiny interface to convert.

### File-upload prototype

CSV upload is the first technical prototype. Ordinary ShinyReact inputs send
JSON, while file upload uses Shiny's file-transfer mechanism. The project must
prove the cleanest supported integration before building the complete Admin
interface.

## Testing and validation

Testing should cover:

- CSV schema and parsing failures.
- Posted-only filtering.
- Exact re-import idempotency.
- The genuine identical-transaction duplicate case.
- Complete-day import behavior.
- Variable and overlapping export ranges.
- Preservation of saved classifications.
- Prospective merchant-rule behavior.
- Allocation-version effective dates.
- The requirement that allocations sum to the budget total.
- Opening balances, zero-transaction months, and rollover calculations.
- Exclusions, reimbursements, refunds, and category offsets.
- Screen-oriented JSON contracts between R and React.
- Browser interactions and responsive layouts.
- Posit Connect Cloud startup and MotherDuck connectivity.

Before the UI relies on the database, the database-backed pipeline must
reproduce the currently validated local results, including transaction counts,
saved reimbursements, category summaries, and monthly rollover balances.

## Implementation sequence

Implementation should proceed in small, reviewable steps.

### 1. Protect the current baseline

- Add tests around the validated pipeline behavior.
- Confirm transaction, duplicate, override, category, and rollover results.
- Reconcile outdated handoff documentation.

### 2. Design the database locally

- Define versioned schema migrations.
- Test against local DuckDB-compatible storage first.
- Seed categories, the initial budget, merchant rules, transactions, and saved
  decisions.

### 3. Validate database equivalence

- Rebuild the current summaries from the database.
- Compare them with the validated local pipeline results.
- Resolve any differences before adding the application interface.

### 4. Add MotherDuck

- Configure server-side credentials.
- Create the production schema only after explicit review.
- Load and validate the initial production history.

### 5. Build the import service

- Implement preview and validation.
- Implement idempotent upsert behavior.
- Add atomic confirmation.

### 6. Prototype ShinyReact

- Install and use the official build-app skill.
- Scaffold the R/Shiny and TypeScript/Vite structure.
- Prove file upload and a small client/server JSON exchange.

### 7. Build a read-only vertical slice

- Add Overview category cards.
- Add month navigation and account freshness.
- Link category selection to a filtered transaction list.

### 8. Add transaction maintenance

- Add search and filters.
- Add the review queue.
- Add mobile transaction cards and three-dot actions.

### 9. Add configuration

- Add merchant-default management.
- Add budget versions, totals, allocations, start date, and opening balances.

### 10. Apply the style guide

- Establish the design tokens and component system.
- Refine responsive behavior and semantic states.
- Validate the experience on phone and desktop sizes.

### 11. Test and deploy

- Complete server, database, contract, and browser tests.
- Build and commit the client assets.
- Deploy to Posit Connect Cloud.
- Verify MotherDuck connectivity and production calculations.

## Remaining implementation-time inputs

The product design is sufficiently settled to begin implementation. The
remaining inputs are:

- MotherDuck database and credential setup.
- Posit Connect Cloud project configuration.
- The result of the ShinyReact file-upload prototype.
