# Budget and categorization rules

## Monthly budget

The initial monthly budget is $6,300. Each category receives its allocation at
the start of the month. Unused amounts roll forward, and overspending creates a
negative balance that future allocations must recover. A month with no imported
transactions still receives its allocation and participates in rollover.

| Category | Monthly allocation |
|---|---:|
| Housing & related expenses | $2,820 |
| Transportation | $500 |
| Food & living expenses | $1,230 |
| Personal & discretionary | $1,100 |
| Rainy day & irregular expenses | $650 |
| **Total** | **$6,300** |

Budget changes apply beginning with their effective month. They do not alter
the allocations or rollover results of earlier months.

## Category intent

- **Housing & related expenses:** rent, mortgage, utilities, internet, and
  recurring home services. Deposits from Brent Hales offset this category.
- **Transportation:** fuel and routine vehicle expenses. Personal airfare and
  related travel do not belong here.
- **Food & living expenses:** groceries and necessary day-to-day, medical, and
  household spending when specifically classified that way.
- **Personal & discretionary:** the default for unmatched spending. It includes
  restaurants, personal travel, recreation, entertainment, optional services,
  and ambiguous retailers unless manually overridden.
- **Rainy day & irregular expenses:** major vehicle or home repairs and similar
  irregular costs.

## Rule precedence

Apply rules in this order:

1. Exclusions and reimbursable designations
2. Transaction-specific overrides
3. Reusable merchant rules
4. Default to Personal & discretionary

The app must retain the source of each category assignment so that defaulted
transactions can be reviewed separately from confirmed rules.

## Transaction treatment

- Import only transactions whose status is `Posted`.
- Negative amounts are candidate expenses. Positive amounts require a type.
- Credit-card payments and internal transfers remain in history but do not
  affect income or spending.
- Positive credit-card transactions other than recognized payments act as
  category credits. They reduce spending in the matched merchant category; an
  unmatched credit requires review.
- Reimbursable expenses and their reimbursement deposits both have zero budget
  effect. Do not credit the budget twice. Reimbursable is a whole-transaction
  designation; partial reimbursements and links between expenses and deposits
  are not modeled.
- Deposits from Brent Hales offset Housing & related expenses regardless of
  amount.
- Miscellaneous income, ordinary payroll deposits, and other unrecognized
  checking inflows do not affect the budget by default.
- Known pass-through inflows and outflows do not affect the budget.
- The identified Utah tax payment is an excluded outflow.
- Unmatched expenses default to Personal & discretionary and remain available
  for review.
- Each transaction has exactly one category and one budget treatment. Split
  transactions are not supported.

## Manual review behavior

A manual category change can apply either to one transaction or become a
reusable merchant rule. Transaction-specific overrides always win. Variable
merchants such as Apple, Target, Home Depot, Venmo, and restaurants should
remain easy to override in the app. Transactions matched by an active merchant
rule do not enter the review queue, but any historical transaction can be
edited later.

Reimbursable airfare choices from the exploratory analysis are provisional
transaction-level decisions. Temporary review numbers are not durable database
identifiers and must not be used as permanent keys.
