import type { ChangeEvent } from "react";

const { React } = window.shinyreact;

type Option = { value: string; label: string };

export type TransactionFilters = {
  start_date: string | null;
  end_date: string | null;
  search: string;
  account: string;
  category: string;
  merchant: string;
  treatment: string;
  review_state: string;
};

export type TransactionRow = {
  transaction_id: string;
  account: string;
  account_label: string;
  date: string;
  description: string;
  amount: number;
  category_code: string | null;
  category: string | null;
  budget_treatment: string;
  display_treatment: string;
  review_state: "pending" | "confirmed";
  is_reimbursable: boolean;
  is_excluded: boolean;
  note: string | null;
  budget_effect: number;
  merchant_rule: string | null;
  merchant: string | null;
};

export type TransactionScreen = {
  status: "ready";
  filters: TransactionFilters;
  options: {
    accounts: Option[];
    categories: Option[];
    merchants: Option[];
    treatments: Option[];
  };
  pending_review_count: number;
  total_count: number;
  displayed_count: number;
  is_truncated: boolean;
  transactions: TransactionRow[];
};

export type TransactionSaveRequest = {
  request_id: string;
  transaction_id: string;
  category_code: string;
  is_reimbursable: boolean;
  is_excluded: boolean;
  note: string | null;
};

export type TransactionSaveResult = {
  status: "idle" | "saved" | "already_saved" | "error";
  request_id?: string | null;
  transaction_id?: string;
  message?: string;
};

const exactCurrency = new Intl.NumberFormat("en-US", {
  style: "currency",
  currency: "USD",
  minimumFractionDigits: 2,
});

const dateFormatter = new Intl.DateTimeFormat("en-US", {
  month: "short",
  day: "numeric",
  year: "numeric",
  timeZone: "UTC",
});

function formatDate(value: string) {
  return dateFormatter.format(new Date(`${value}T00:00:00Z`));
}

export function filtersForMonth(month: string): TransactionFilters {
  const [year, monthNumber] = month.split("-").map(Number);
  const lastDay = new Date(Date.UTC(year, monthNumber, 0)).getUTCDate();

  return {
    start_date: month,
    end_date: `${year}-${String(monthNumber).padStart(2, "0")}-${String(lastDay).padStart(2, "0")}`,
    search: "",
    account: "all",
    category: "all",
    merchant: "all",
    treatment: "all",
    review_state: "all",
  };
}

export function reviewQueueFilters(): TransactionFilters {
  return {
    start_date: null,
    end_date: null,
    search: "",
    account: "all",
    category: "all",
    merchant: "all",
    treatment: "all",
    review_state: "pending",
  };
}

function treatmentLabel(treatment: string) {
  const labels: Record<string, string> = {
    expense: "Spending",
    refund: "Refund",
    category_offset: "Category offset",
    reimbursement: "Reimbursement",
    transfer_or_card_payment: "Transfer or card payment",
    excluded_inflow: "Excluded inflow",
    excluded_outflow: "Excluded outflow",
    pass_through: "Pass-through",
    needs_review: "Needs review",
    reimbursable: "Reimbursable",
    excluded: "Excluded",
  };
  return labels[treatment] ?? treatment;
}

function SelectFilter({
  label,
  options,
  value,
  onChange,
}: {
  label: string;
  options: Option[];
  value: string;
  onChange: (value: string) => void;
}) {
  return (
    <label className="filter-field">
      <span>{label}</span>
      <select value={value} onChange={(event) => onChange(event.target.value)}>
        <option value="all">All</option>
        {options.map((option) => (
          <option key={option.value} value={option.value}>{option.label}</option>
        ))}
      </select>
    </label>
  );
}

function TransactionFiltersPanel({
  filters,
  options,
  onChange,
  onReset,
}: {
  filters: TransactionFilters;
  options: TransactionScreen["options"];
  onChange: React.Dispatch<React.SetStateAction<TransactionFilters>>;
  onReset: () => void;
}) {
  const update = <K extends keyof TransactionFilters>(key: K, value: TransactionFilters[K]) => {
    onChange((current) => ({ ...current, [key]: value }));
  };

  return (
    <section className="transaction-filters" aria-label="Transaction filters">
      <label className="filter-field search-filter">
        <span>Search merchant or description</span>
        <input
          onChange={(event: ChangeEvent<HTMLInputElement>) => update("search", event.target.value)}
          placeholder="Search transactions"
          type="search"
          value={filters.search}
        />
      </label>
      <label className="filter-field">
        <span>From</span>
        <input
          onChange={(event) => update("start_date", event.target.value || null)}
          type="date"
          value={filters.start_date ?? ""}
        />
      </label>
      <label className="filter-field">
        <span>Through</span>
        <input
          onChange={(event) => update("end_date", event.target.value || null)}
          type="date"
          value={filters.end_date ?? ""}
        />
      </label>
      <SelectFilter
        label="Account"
        onChange={(value) => update("account", value)}
        options={options.accounts}
        value={filters.account}
      />
      <SelectFilter
        label="Category"
        onChange={(value) => update("category", value)}
        options={options.categories}
        value={filters.category}
      />
      <SelectFilter
        label="Merchant default"
        onChange={(value) => update("merchant", value)}
        options={options.merchants}
        value={filters.merchant}
      />
      <SelectFilter
        label="Budget treatment"
        onChange={(value) => update("treatment", value)}
        options={options.treatments}
        value={filters.treatment}
      />
      <label className="filter-field">
        <span>Review state</span>
        <select
          onChange={(event) => update("review_state", event.target.value)}
          value={filters.review_state}
        >
          <option value="all">All</option>
          <option value="pending">Pending</option>
          <option value="confirmed">Confirmed</option>
        </select>
      </label>
      <button className="secondary-button reset-filters" onClick={onReset} type="button">
        Reset filters
      </button>
    </section>
  );
}

function TransactionEditor({
  categories,
  onCancel,
  onSave,
  saveResult,
  transaction,
}: {
  categories: Option[];
  onCancel: () => void;
  onSave: (request: TransactionSaveRequest) => void;
  saveResult: TransactionSaveResult | null | undefined;
  transaction: TransactionRow;
}) {
  const [category, setCategory] = React.useState(
    transaction.category_code ?? "personal_discretionary",
  );
  const [isReimbursable, setIsReimbursable] = React.useState(transaction.is_reimbursable);
  const [isExcluded, setIsExcluded] = React.useState(transaction.is_excluded);
  const [note, setNote] = React.useState(transaction.note ?? "");
  const [requestId, setRequestId] = React.useState<string | null>(null);
  const isSaving = Boolean(requestId) && saveResult?.request_id !== requestId;

  React.useEffect(() => {
    if (
      requestId &&
      saveResult?.request_id === requestId &&
      (saveResult.status === "saved" || saveResult.status === "already_saved")
    ) {
      onCancel();
    }
  }, [onCancel, requestId, saveResult]);

  const submit = () => {
    const nextRequestId = crypto.randomUUID();
    setRequestId(nextRequestId);
    onSave({
      request_id: nextRequestId,
      transaction_id: transaction.transaction_id,
      category_code: category,
      is_reimbursable: isReimbursable,
      is_excluded: isExcluded,
      note: note.trim() || null,
    });
  };

  return (
    <div className="decision-editor">
      <div className="editor-fields">
        <label className="filter-field">
          <span>Category</span>
          <select value={category} onChange={(event) => setCategory(event.target.value)}>
            {categories.map((option) => (
              <option key={option.value} value={option.value}>{option.label}</option>
            ))}
          </select>
        </label>
        <label className="check-field">
          <input
            checked={isReimbursable}
            onChange={(event) => setIsReimbursable(event.target.checked)}
            type="checkbox"
          />
          <span>Reimbursable</span>
        </label>
        <label className="check-field">
          <input
            checked={isExcluded}
            onChange={(event) => setIsExcluded(event.target.checked)}
            type="checkbox"
          />
          <span>Exclude from budget</span>
        </label>
        <label className="filter-field note-field">
          <span>Decision note</span>
          <textarea
            maxLength={500}
            onChange={(event) => setNote(event.target.value)}
            placeholder="Optional context for this decision"
            value={note}
          />
        </label>
      </div>
      {saveResult?.status === "error" && saveResult.request_id === requestId && (
        <div className="notice notice-error" role="alert">{saveResult.message}</div>
      )}
      <div className="editor-actions">
        <button className="secondary-button" disabled={isSaving} onClick={onCancel} type="button">
          Cancel
        </button>
        <button className="primary-button" disabled={isSaving} onClick={submit} type="button">
          {isSaving ? "Saving…" : "Save decision"}
        </button>
      </div>
      <p className="editor-note">This changes only this transaction. Merchant defaults are managed separately.</p>
    </div>
  );
}

export default function TransactionsView({
  filters,
  isReviewQueue,
  onBack,
  onFiltersChange,
  onReset,
  onSave,
  saveResult,
  screen,
}: {
  filters: TransactionFilters;
  isReviewQueue: boolean;
  onBack: () => void;
  onFiltersChange: React.Dispatch<React.SetStateAction<TransactionFilters>>;
  onReset: () => void;
  onSave: (request: TransactionSaveRequest) => void;
  saveResult: TransactionSaveResult | null | undefined;
  screen: TransactionScreen;
}) {
  const [editingId, setEditingId] = React.useState<string | null>(null);

  return (
    <main>
      <button className="back-link" onClick={onBack} type="button">
        <span aria-hidden="true">←</span> Back to Overview
      </button>
      <section className="transactions-heading" aria-labelledby="transactions-title">
        <div>
          <p className="eyebrow">{isReviewQueue ? "Review queue" : "Transactions"}</p>
          <h1 id="transactions-title">
            {isReviewQueue ? "Decisions waiting for review" : "Transaction history"}
          </h1>
          <p className="lede">
            {isReviewQueue
              ? "Confirm or correct uncertain new transactions before they leave the queue."
              : "Search the stored history and make deliberate one-off corrections."}
          </p>
        </div>
        <span className="count-label">
          {screen.total_count} {screen.total_count === 1 ? "transaction" : "transactions"}
        </span>
      </section>

      {saveResult?.status === "saved" && (
        <div className="notice notice-success" role="status">Transaction decision saved.</div>
      )}

      <TransactionFiltersPanel
        filters={filters}
        onChange={onFiltersChange}
        onReset={onReset}
        options={screen.options}
      />

      {screen.is_truncated && (
        <p className="result-note">
          Showing the first {screen.displayed_count} of {screen.total_count} matches. Narrow the filters to see the rest.
        </p>
      )}

      {screen.transactions.length === 0 ? (
        <div className="empty-state transaction-empty">
          <p className="empty-title">No matching transactions</p>
          <p>{isReviewQueue ? "Nothing is waiting for review." : "Try changing or resetting the filters."}</p>
        </div>
      ) : (
        <div className="maintenance-list" role="list">
          {screen.transactions.map((transaction) => {
            const isCredit = transaction.budget_effect < 0;
            const isEditing = editingId === transaction.transaction_id;
            return (
              <article
                className={isEditing ? "maintenance-row editing" : "maintenance-row"}
                key={transaction.transaction_id}
                role="listitem"
              >
                <div className="transaction-summary">
                  <div className="transaction-description">
                    <strong>{transaction.description}</strong>
                    <span>{formatDate(transaction.date)} · {transaction.account_label}</span>
                  </div>
                  <div className="transaction-category">
                    <span>Category</span>
                    <strong>{transaction.category ?? "Uncategorized"}</strong>
                    {transaction.merchant && <small>Default: {transaction.merchant}</small>}
                  </div>
                  <span className={`treatment treatment-${transaction.display_treatment}`}>
                    {treatmentLabel(transaction.display_treatment)}
                  </span>
                  {transaction.review_state === "pending" && (
                    <span className="review-tag">Needs review</span>
                  )}
                  <div className={isCredit ? "transaction-amount credit" : "transaction-amount"}>
                    <strong>{exactCurrency.format(transaction.budget_effect)}</strong>
                    <span>budget effect · source {exactCurrency.format(Math.abs(transaction.amount))}</span>
                  </div>
                  <button
                    aria-expanded={isEditing}
                    aria-label={`More actions for ${transaction.description}`}
                    className="more-actions"
                    onClick={() => setEditingId(isEditing ? null : transaction.transaction_id)}
                    type="button"
                  >
                    <span aria-hidden="true">•••</span>
                  </button>
                </div>
                {isEditing && (
                  <TransactionEditor
                    categories={screen.options.categories}
                    key={transaction.transaction_id}
                    onCancel={() => setEditingId(null)}
                    onSave={onSave}
                    saveResult={saveResult}
                    transaction={transaction}
                  />
                )}
              </article>
            );
          })}
        </div>
      )}
    </main>
  );
}
