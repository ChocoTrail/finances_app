CREATE TABLE categories (
  category_code VARCHAR PRIMARY KEY,
  display_name VARCHAR NOT NULL UNIQUE,
  sort_order INTEGER NOT NULL UNIQUE CHECK (sort_order > 0),
  is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE imports (
  import_id VARCHAR PRIMARY KEY,
  account VARCHAR NOT NULL CHECK (
    account IN ('checking', 'credit_card_jacob', 'credit_card_kendra')
  ),
  source_filename VARCHAR NOT NULL,
  imported_at TIMESTAMP NOT NULL,
  coverage_start DATE,
  coverage_end DATE,
  source_row_count INTEGER NOT NULL CHECK (source_row_count >= 0),
  posted_row_count INTEGER NOT NULL CHECK (posted_row_count >= 0),
  new_transaction_count INTEGER NOT NULL CHECK (new_transaction_count >= 0),
  known_transaction_count INTEGER NOT NULL CHECK (known_transaction_count >= 0),
  outcome VARCHAR NOT NULL CHECK (outcome IN ('successful', 'failed')),
  error_message VARCHAR,
  CHECK (coverage_end IS NULL OR coverage_start IS NULL OR coverage_end >= coverage_start),
  CHECK (
    (outcome = 'successful' AND error_message IS NULL) OR
    (outcome = 'failed' AND error_message IS NOT NULL)
  )
);

CREATE TABLE transactions (
  transaction_id VARCHAR PRIMARY KEY,
  account VARCHAR NOT NULL CHECK (
    account IN ('checking', 'credit_card_jacob', 'credit_card_kendra')
  ),
  transaction_date DATE NOT NULL,
  original_description VARCHAR NOT NULL,
  original_amount DECIMAL(18, 2) NOT NULL,
  original_check_number VARCHAR,
  standardized_description VARCHAR NOT NULL,
  standardized_amount DECIMAL(18, 2) NOT NULL,
  standardized_check_number VARCHAR,
  duplicate_sequence INTEGER NOT NULL CHECK (duplicate_sequence > 0),
  composite_identity VARCHAR NOT NULL UNIQUE,
  raw_transaction_json VARCHAR NOT NULL,
  first_seen_import_id VARCHAR NOT NULL REFERENCES imports(import_id),
  last_seen_import_id VARCHAR NOT NULL REFERENCES imports(import_id),
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

CREATE TABLE transaction_decisions (
  transaction_id VARCHAR PRIMARY KEY REFERENCES transactions(transaction_id),
  category_code VARCHAR REFERENCES categories(category_code),
  assignment_source VARCHAR CHECK (
    assignment_source IN (
      'transaction_type_rule',
      'transaction_override',
      'merchant_rule',
      'default'
    )
  ),
  assignment_rule VARCHAR,
  review_state VARCHAR NOT NULL CHECK (
    review_state IN ('pending', 'confirmed')
  ),
  budget_treatment VARCHAR NOT NULL CHECK (
    budget_treatment IN (
      'expense',
      'refund',
      'category_offset',
      'reimbursement',
      'transfer_or_card_payment',
      'excluded_inflow',
      'excluded_outflow',
      'pass_through',
      'needs_review'
    )
  ),
  is_reimbursable BOOLEAN NOT NULL DEFAULT FALSE,
  is_excluded BOOLEAN NOT NULL DEFAULT FALSE,
  note VARCHAR,
  updated_at TIMESTAMP NOT NULL,
  CHECK (category_code IS NOT NULL OR assignment_source IS NULL)
);

CREATE TABLE merchant_rules (
  rule_id VARCHAR PRIMARY KEY,
  display_name VARCHAR NOT NULL,
  description_pattern VARCHAR NOT NULL,
  match_type VARCHAR NOT NULL DEFAULT 'regular_expression' CHECK (
    match_type IN ('regular_expression')
  ),
  default_category_code VARCHAR NOT NULL REFERENCES categories(category_code),
  effective_date DATE NOT NULL,
  priority INTEGER NOT NULL UNIQUE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

CREATE TABLE budget_versions (
  budget_version_id VARCHAR PRIMARY KEY,
  effective_month DATE NOT NULL UNIQUE,
  total_monthly_budget DECIMAL(18, 2) NOT NULL CHECK (total_monthly_budget > 0),
  created_at TIMESTAMP NOT NULL,
  CHECK (effective_month = date_trunc('month', effective_month))
);

CREATE TABLE budget_allocations (
  budget_version_id VARCHAR NOT NULL REFERENCES budget_versions(budget_version_id),
  category_code VARCHAR NOT NULL REFERENCES categories(category_code),
  monthly_allocation DECIMAL(18, 2) NOT NULL CHECK (monthly_allocation >= 0),
  PRIMARY KEY (budget_version_id, category_code)
);

CREATE TABLE budget_opening_balances (
  category_code VARCHAR PRIMARY KEY REFERENCES categories(category_code),
  budget_start_month DATE NOT NULL,
  opening_balance DECIMAL(18, 2) NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  CHECK (budget_start_month = date_trunc('month', budget_start_month))
);

CREATE TABLE decision_audit_log (
  audit_id VARCHAR PRIMARY KEY,
  entity_type VARCHAR NOT NULL CHECK (
    entity_type IN ('transaction_decision', 'merchant_rule', 'budget_version', 'opening_balance')
  ),
  entity_id VARCHAR NOT NULL,
  action VARCHAR NOT NULL,
  changed_at TIMESTAMP NOT NULL,
  before_json VARCHAR,
  after_json VARCHAR NOT NULL,
  change_note VARCHAR
);

CREATE INDEX transactions_account_date_idx
  ON transactions (account, transaction_date);

CREATE INDEX transaction_decisions_review_idx
  ON transaction_decisions (review_state, category_code);

CREATE INDEX merchant_rules_active_idx
  ON merchant_rules (is_active, priority);

CREATE INDEX decision_audit_entity_idx
  ON decision_audit_log (entity_type, entity_id, changed_at);
