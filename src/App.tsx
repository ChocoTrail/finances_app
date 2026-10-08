import TransactionsView, {
  filtersForMonth,
  reviewQueueFilters,
  type TransactionFilters,
  type TransactionSaveRequest,
  type TransactionSaveResult,
  type TransactionScreen,
} from "@/TransactionsView";
import AdminView, {
  type ConfigurationSaveRequest,
  type ConfigurationSaveResult,
  type ConfigurationScreen,
} from "@/AdminView";

const {
  React,
  ShinyOutput,
  useShinyBusy,
  useShinyInitialized,
  useShinyInput,
  useShinyOutputError,
  useShinyOutputStatus,
  useShinyOutputValue,
} = window.shinyreact;

type Account = "checking" | "credit_card_jacob" | "credit_card_kendra";
type View = "overview" | "transactions" | "review" | "admin";

type CategoryCard = {
  category_code: string;
  name: string;
  monthly_allocation: number;
  net_spending: number;
  opening_rollover: number;
  available_balance: number;
  balance_state: "available" | "deficit";
};

type AccountFreshness = {
  account: Account;
  label: string;
  data_through: string | null;
  last_updated: string | null;
};

type OverviewScreen = {
  status: "ready";
  selected_month: string;
  month_label: string;
  current_month: string;
  budget_start_month: string;
  previous_month: string | null;
  next_month: string | null;
  categories: CategoryCard[];
  accounts: AccountFreshness[];
};

type ImportProblem = {
  code: string;
  severity: "error" | "warning";
  source_row_number: number | null;
  message: string;
};

type ImportPreview = {
  status: "waiting" | "ready" | "invalid" | "error";
  account: Account | null;
  source_filename: string | null;
  coverage_start: string | null;
  coverage_end: string | null;
  source_row_count: number;
  posted_row_count: number;
  new_transaction_count: number;
  known_transaction_count: number;
  duplicate_group_count: number;
  can_confirm: boolean;
  problems: ImportProblem[];
  account_slot_notice: string | null;
  complete_day_notice: string;
  message?: string;
};

type ImportConfirmRequest = {
  request_id: string;
  confirmed_account: Account;
  confirmed_filename: string;
  account_and_dates_verified: boolean;
};

type ImportSaveResult = {
  status: "idle" | "saved" | "already_saved" | "error";
  request_id?: string | null;
  import_id?: string;
  new_transaction_count?: number;
  known_transaction_count?: number;
  message?: string;
};

type ConnectionStatus = {
  status: "ready" | "error";
  message?: string;
};

const accounts: Array<{ value: Account; label: string }> = [
  { value: "checking", label: "Checking" },
  { value: "credit_card_jacob", label: "Jacob’s credit card" },
  { value: "credit_card_kendra", label: "Kendra’s credit card" },
];

const currency = new Intl.NumberFormat("en-US", {
  style: "currency",
  currency: "USD",
  maximumFractionDigits: 0,
});

const dateFormatter = new Intl.DateTimeFormat("en-US", {
  month: "short",
  day: "numeric",
  year: "numeric",
  timeZone: "UTC",
});

const overviewCategoryOrder = [
  "food_living",
  "personal_discretionary",
  "transportation",
  "rainy_day",
  "housing",
];

function localCurrentMonth() {
  const today = new Date();
  const year = today.getFullYear();
  const month = String(today.getMonth() + 1).padStart(2, "0");
  return `${year}-${month}-01`;
}

function formatDate(value: string) {
  return dateFormatter.format(new Date(`${value}T00:00:00Z`));
}

function Metric({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="metric">
      <dt>{label}</dt>
      <dd>{value}</dd>
    </div>
  );
}

function LoadingPanel({ label }: { label: string }) {
  return (
    <div className="screen-state" role="status">
      <span className="loading-mark" aria-hidden="true" />
      <p>{label}</p>
    </div>
  );
}

function OutputError({ message }: { message: string }) {
  return (
    <div className="notice notice-error screen-error" role="alert">
      <strong>Couldn’t load this view.</strong> {message}
    </div>
  );
}

function ConnectionUnavailable({ message, onRetry }: {
  message: string;
  onRetry: () => void;
}) {
  return (
    <main className="connection-error">
      <div className="panel connection-error-panel" role="alert">
        <p className="eyebrow">Connection unavailable</p>
        <h1>We couldn’t reach the finance database</h1>
        <p>{message}</p>
        <button className="primary-button" onClick={onRetry} type="button">
          Try again
        </button>
      </div>
    </main>
  );
}

function MonthNavigation({ overview, onChange }: {
  overview: OverviewScreen;
  onChange: (month: string) => void;
}) {
  return (
    <div className="month-navigation" aria-label="Budget month">
      <button
        aria-label="Previous month"
        disabled={!overview.previous_month}
        onClick={() => overview.previous_month && onChange(overview.previous_month)}
        type="button"
      >
        <span aria-hidden="true">←</span>
      </button>
      <div>
        <span>Budget month</span>
        <strong>{overview.month_label}</strong>
      </div>
      <button
        aria-label="Next month"
        disabled={!overview.next_month}
        onClick={() => overview.next_month && onChange(overview.next_month)}
        type="button"
      >
        <span aria-hidden="true">→</span>
      </button>
    </div>
  );
}

function AccountFreshnessList({ accounts: freshness }: { accounts: AccountFreshness[] }) {
  return (
    <section className="freshness" aria-labelledby="freshness-title">
      <div>
        <p className="eyebrow">Update context</p>
        <h2 id="freshness-title">Account data</h2>
      </div>
      <ul>
        {freshness.map((account) => (
          <li key={account.account}>
            <span>{account.label}</span>
            <strong>
              {account.data_through ? `Through ${formatDate(account.data_through)}` : "No imports yet"}
            </strong>
          </li>
        ))}
      </ul>
    </section>
  );
}

function CategoryCardView({ category, monthLabel, onSelect }: {
  category: CategoryCard;
  monthLabel: string;
  onSelect: (categoryCode: string) => void;
}) {
  const progress = category.monthly_allocation > 0
    ? Math.max(0, Math.min(100, (category.net_spending / category.monthly_allocation) * 100))
    : 0;
  const spendingText = category.net_spending < 0
    ? `${currency.format(Math.abs(category.net_spending))} net credit`
    : `${currency.format(category.net_spending)} spent`;

  return (
    <button
      aria-label={`View ${category.name} transactions for ${monthLabel}`}
      className={category.balance_state === "deficit" ? "category-card deficit" : "category-card"}
      onClick={() => onSelect(category.category_code)}
      type="button"
    >
      <span className="card-title">{category.name}</span>
      <span className="budget-label">Monthly budget</span>
      <strong className="category-budget">{currency.format(category.monthly_allocation)}</strong>
      <span className="spending-line">
        <span>{spendingText}</span>
        <span>{progress.toFixed(0)}%</span>
      </span>
      <span className="progress-track" aria-hidden="true">
        <span style={{ width: `${progress}%` }} />
      </span>
      <span className="rollover-balance">
        <span>{category.balance_state === "deficit" ? "Balance with rollover" : "Available with rollover"}</span>
        <strong>{currency.format(category.available_balance)}</strong>
      </span>
      <span className="card-link">View transactions <span aria-hidden="true">→</span></span>
    </button>
  );
}

function OverviewView({ overview, onMonthChange, onSelectCategory }: {
  overview: OverviewScreen;
  onMonthChange: (month: string) => void;
  onSelectCategory: (categoryCode: string) => void;
}) {
  const totalMonthlyBudget = overview.categories.reduce(
    (total, category) => total + category.monthly_allocation,
    0,
  );
  const orderedCategories = [...overview.categories].sort((left, right) => {
    const leftIndex = overviewCategoryOrder.indexOf(left.category_code);
    const rightIndex = overviewCategoryOrder.indexOf(right.category_code);
    return (leftIndex === -1 ? overviewCategoryOrder.length : leftIndex)
      - (rightIndex === -1 ? overviewCategoryOrder.length : rightIndex);
  });

  return (
    <main>
      <section className="overview-heading" aria-labelledby="overview-title">
        <div>
          <p className="eyebrow">Overview</p>
          <h1 id="overview-title">Your monthly budget</h1>
          <p className="lede">See what you planned for this month and how spending is tracking.</p>
        </div>
        <MonthNavigation overview={overview} onChange={onMonthChange} />
      </section>

      <section className="budget-summary" aria-labelledby="budget-total-title">
        <div>
          <p className="eyebrow">Total monthly budget</p>
          <h2 id="budget-total-title">{currency.format(totalMonthlyBudget)}</h2>
        </div>
        <p>{overview.month_label} · allocated across {overview.categories.length} categories</p>
      </section>

      <AccountFreshnessList accounts={overview.accounts} />

      <section aria-labelledby="categories-title">
        <div className="section-heading compact-heading">
          <div>
            <p className="eyebrow">Monthly budget by category</p>
            <h2 id="categories-title">{overview.month_label}</h2>
          </div>
          <p>Rollover balances are shown as supporting context.</p>
        </div>
        <div className="category-grid">
          {orderedCategories.map((category) => (
            <CategoryCardView
              category={category}
              key={category.category_code}
              monthLabel={overview.month_label}
              onSelect={onSelectCategory}
            />
          ))}
        </div>
      </section>
    </main>
  );
}

function PreviewPanel({ preview, onConfirm, saveResult }: {
  preview: ImportPreview | null | undefined;
  onConfirm: (request: ImportConfirmRequest) => void;
  saveResult: ImportSaveResult | null | undefined;
}) {
  const status = useShinyOutputStatus("import_preview");
  const error = useShinyOutputError("import_preview");
  const [verified, setVerified] = React.useState(false);
  const [requestId, setRequestId] = React.useState<string | null>(null);
  const previewIdentity = preview && preview.status !== "waiting"
    ? `${preview.account}|${preview.source_filename}|${preview.coverage_start}|${preview.coverage_end}|${preview.posted_row_count}`
    : "waiting";

  React.useEffect(() => {
    setVerified(false);
    setRequestId(null);
  }, [previewIdentity]);

  if (error) return <OutputError message={error.message} />;

  if (!preview || preview.status === "waiting") {
    return (
      <div className="empty-state">
        <p className="empty-title">No file selected</p>
        <p>Choose an account export to preview it before anything is saved.</p>
      </div>
    );
  }

  if (preview.status === "error") {
    return <OutputError message={preview.message ?? "The preview failed."} />;
  }

  const matchingResult = saveResult?.request_id === requestId ? saveResult : null;
  const isSaving = Boolean(requestId) && !matchingResult;
  const isSaved = matchingResult?.status === "saved" || matchingResult?.status === "already_saved";
  const accountLabel = accounts.find((option) => option.value === preview.account)?.label ?? preview.account;
  const confirm = () => {
    if (!preview.account || !preview.source_filename) return;
    const nextRequestId = `import-${crypto.randomUUID()}`;
    setRequestId(nextRequestId);
    onConfirm({
      request_id: nextRequestId,
      confirmed_account: preview.account,
      confirmed_filename: preview.source_filename,
      account_and_dates_verified: verified,
    });
  };

  return (
    <div className={status === "recalculating" ? "preview recalculating" : "preview"}>
      <div className="preview-heading">
        <div>
          <p className="eyebrow">Import preview</p>
          <h2>{preview.source_filename}</h2>
        </div>
        <span className={preview.can_confirm ? "status status-ready" : "status status-error"}>
          {preview.can_confirm ? "Ready for confirmation" : "Needs attention"}
        </span>
      </div>

      <dl className="metrics-grid">
        <Metric label="Coverage" value={`${preview.coverage_start} – ${preview.coverage_end}`} />
        <Metric label="Source rows" value={preview.source_row_count} />
        <Metric label="Posted" value={preview.posted_row_count} />
        <Metric label="New" value={preview.new_transaction_count} />
        <Metric label="Already known" value={preview.known_transaction_count} />
        <Metric label="Duplicate groups" value={preview.duplicate_group_count} />
      </dl>

      {preview.problems.length > 0 && (
        <div className="problem-list" aria-label="Import problems">
          {preview.problems.map((problem, index) => (
            <div
              className={`notice ${problem.severity === "error" ? "notice-error" : "notice-warning"}`}
              key={`${problem.code}-${problem.source_row_number ?? "file"}-${index}`}
            >
              <strong>{problem.severity === "error" ? "Error" : "Note"}</strong>
              {problem.source_row_number ? ` · row ${problem.source_row_number}` : ""}: {problem.message}
            </div>
          ))}
        </div>
      )}

      <div className="confirmation-copy">
        <p>{preview.account_slot_notice}</p>
        <p>{preview.complete_day_notice}</p>
      </div>

      {preview.can_confirm && (
        <section className="import-confirmation" aria-labelledby="confirm-import-title">
          <div>
            <p className="eyebrow">Final check</p>
            <h3 id="confirm-import-title">Confirm this import</h3>
          </div>
          <dl className="confirmation-details">
            <div><dt>Account</dt><dd>{accountLabel}</dd></div>
            <div><dt>File</dt><dd>{preview.source_filename}</dd></div>
            <div><dt>Coverage</dt><dd>{preview.coverage_start} – {preview.coverage_end}</dd></div>
            <div><dt>Posted transactions</dt><dd>{preview.posted_row_count}</dd></div>
          </dl>
          <label className={verified ? "check-field deliberate selected" : "check-field deliberate"}>
            <input
              checked={verified}
              disabled={isSaving || isSaved}
              onChange={(event) => setVerified(event.target.checked)}
              type="checkbox"
            />
            <span>I verified the account slot and that this export contains complete calendar days.</span>
          </label>
          {matchingResult?.status === "error" && (
            <div className="notice notice-error" role="alert">
              <strong>Import failed.</strong> {matchingResult.message}
            </div>
          )}
          {isSaved && (
            <div className="notice notice-success" role="status">
              <strong>Import saved.</strong> {matchingResult?.new_transaction_count ?? 0} new and {matchingResult?.known_transaction_count ?? 0} known transactions were processed.
            </div>
          )}
          <button
            className="primary-button"
            disabled={!verified || isSaving || isSaved}
            onClick={confirm}
            type="button"
          >
            {isSaving ? "Importing…" : isSaved ? "Import complete" : "Confirm import"}
          </button>
        </section>
      )}
    </div>
  );
}

function ImportAdmin({ account, onConfirm, preview, saveResult, setAccount }: {
  account: Account;
  onConfirm: (request: ImportConfirmRequest) => void;
  preview: ImportPreview | null | undefined;
  saveResult: ImportSaveResult | null | undefined;
  setAccount: (account: Account) => void;
}) {
  return (
    <div className="admin-import">
      <section className="panel" aria-labelledby="upload-title">
        <div className="section-heading">
          <div>
            <p className="eyebrow">File transfer</p>
            <h2 id="upload-title">Preview an account export</h2>
          </div>
          <p>Select the account slot before choosing its complete-day CSV export.</p>
        </div>

        <fieldset className="account-picker">
          <legend>Account slot</legend>
          <div className="account-options">
            {accounts.map((option) => (
              <label
                className={account === option.value ? "account-option selected" : "account-option"}
                key={option.value}
              >
                <input
                  checked={account === option.value}
                  name="account-slot"
                  onChange={() => setAccount(option.value)}
                  type="radio"
                  value={option.value}
                />
                <span>{option.label}</span>
              </label>
            ))}
          </div>
        </fieldset>

        <ShinyOutput id="upload_widget" className="shiny-html-output upload-holder" />
        <PreviewPanel onConfirm={onConfirm} preview={preview} saveResult={saveResult} />
      </section>
    </div>
  );
}

export default function App() {
  const initialized = useShinyInitialized();
  const busy = useShinyBusy();
  const [view, setView] = React.useState<View>("overview");
  const [, setMonth] = useShinyInput("overview_month", localCurrentMonth(), { debounceMs: 0 });
  const [, setSelectedCategory] = useShinyInput<string | null>(
    "overview_category",
    null,
    { debounceMs: 0 },
  );
  const initialTransactionFilters = filtersForMonth(localCurrentMonth());
  const [transactionFilters, setTransactionFilters] = React.useState<TransactionFilters>(
    initialTransactionFilters,
  );
  const [, setTransactionFilterInput] = useShinyInput<TransactionFilters>(
    "transaction_filters",
    initialTransactionFilters,
    { debounceMs: 180 },
  );
  const [, setTransactionSaveRequest] = useShinyInput<TransactionSaveRequest | null>(
    "transaction_save_request",
    null,
    { priority: "event" },
  );
  const [, setConfigurationSaveRequest] = useShinyInput<ConfigurationSaveRequest | null>(
    "configuration_save_request", null, { priority: "event" },
  );
  const [, setImportConfirmRequest] = useShinyInput<ImportConfirmRequest | null>(
    "import_confirm_request", null, { priority: "event" },
  );
  const [, setConnectionRetryRequest] = useShinyInput<string | null>(
    "connection_retry_request", null, { priority: "event" },
  );
  const [account, setAccount] = useShinyInput<Account>("account_slot", "checking", { debounceMs: 0 });
  const overview = useShinyOutputValue<OverviewScreen | null>("overview_screen", null);
  const overviewError = useShinyOutputError("overview_screen");
  const overviewStatus = useShinyOutputStatus("overview_screen");
  const transactionScreen = useShinyOutputValue<TransactionScreen | null>("transaction_screen", null);
  const transactionError = useShinyOutputError("transaction_screen");
  const transactionStatus = useShinyOutputStatus("transaction_screen");
  const transactionSaveResult = useShinyOutputValue<TransactionSaveResult | null>(
    "transaction_save_result",
    null,
  );
  const configurationScreen = useShinyOutputValue<ConfigurationScreen | null>("configuration_screen", null);
  const configurationError = useShinyOutputError("configuration_screen");
  const configurationStatus = useShinyOutputStatus("configuration_screen");
  const configurationSaveResult = useShinyOutputValue<ConfigurationSaveResult | null>("configuration_save_result", null);
  const preview = useShinyOutputValue<ImportPreview | null>("import_preview", null);
  const importSaveResult = useShinyOutputValue<ImportSaveResult | null>("import_save_result", null);
  const connectionStatus = useShinyOutputValue<ConnectionStatus | null>("connection_status", null);

  React.useEffect(() => {
    setTransactionFilterInput(transactionFilters);
  }, [transactionFilters]);

  if (!initialized) return null;

  const changeMonth = (nextMonth: string) => {
    setSelectedCategory(null);
    setMonth(nextMonth);
    setView("overview");
  };

  const openCategory = (categoryCode: string) => {
    setSelectedCategory(categoryCode);
    setTransactionFilters({
      ...filtersForMonth(overview?.selected_month ?? localCurrentMonth()),
      category: categoryCode,
    });
    setView("transactions");
  };

  const openTransactionHistory = () => {
    setTransactionFilters(filtersForMonth(overview?.selected_month ?? localCurrentMonth()));
    setView("transactions");
  };

  const openReviewQueue = () => {
    setTransactionFilters(reviewQueueFilters());
    setView("review");
  };

  const resetTransactionFilters = () => {
    setTransactionFilters(
      view === "review"
        ? reviewQueueFilters()
        : filtersForMonth(overview?.selected_month ?? localCurrentMonth()),
    );
  };

  return (
    <div className={busy ? "app-shell busy" : "app-shell"}>
      <a className="skip-link" href="#main-content">Skip to main content</a>
      <div className="activity-line" aria-hidden="true" />
      <header className="site-header">
        <a className="product-name" href="#" onClick={(event) => {
          event.preventDefault();
          setView("overview");
        }}>
          Family finances
        </a>
        <nav aria-label="Primary navigation">
          <button
            aria-current={view === "overview" ? "page" : undefined}
            onClick={() => setView("overview")}
            type="button"
          >
            Overview
          </button>
          <button
            aria-label="Transactions"
            aria-current={view === "transactions" ? "page" : undefined}
            onClick={openTransactionHistory}
            type="button"
          >
            <span className="nav-label-full">Transactions</span>
            <span className="nav-label-compact" aria-hidden="true">History</span>
          </button>
          <button
            aria-current={view === "review" ? "page" : undefined}
            onClick={openReviewQueue}
            type="button"
          >
            Review
            {transactionScreen && transactionScreen.pending_review_count > 0 && (
              <span className="nav-count">{transactionScreen.pending_review_count}</span>
            )}
          </button>
          <button
            aria-current={view === "admin" ? "page" : undefined}
            onClick={() => setView("admin")}
            type="button"
          >
            Admin
          </button>
        </nav>
      </header>

      <div id="main-content" tabIndex={-1}>
        {!connectionStatus ? (
          <main><LoadingPanel label="Connecting to your finance data…" /></main>
        ) : connectionStatus.status === "error" ? (
          <ConnectionUnavailable
            message={connectionStatus.message ?? "The finance database is unavailable."}
            onRetry={() => setConnectionRetryRequest(`retry-${crypto.randomUUID()}`)}
          />
        ) : view === "admin" ? (
          configurationError ? <main><OutputError message={configurationError.message} /></main>
          : !configurationScreen ? <main><LoadingPanel label="Loading configuration…" /></main>
          : <div className={configurationStatus === "recalculating" ? "recalculating" : ""}>
            <AdminView
              screen={configurationScreen}
              saveResult={configurationSaveResult ?? null}
              onSave={setConfigurationSaveRequest}
              importContent={<ImportAdmin account={account} onConfirm={setImportConfirmRequest} preview={preview} saveResult={importSaveResult} setAccount={setAccount} />}
            />
          </div>
        ) : view === "transactions" || view === "review" ? (
          transactionError ? (
            <main><OutputError message={transactionError.message} /></main>
          ) : !transactionScreen ? (
            <main><LoadingPanel label="Loading transactions…" /></main>
          ) : (
            <div className={transactionStatus === "recalculating" ? "recalculating" : ""}>
              <TransactionsView
                filters={transactionFilters}
                isReviewQueue={view === "review"}
                onBack={() => setView("overview")}
                onFiltersChange={setTransactionFilters}
                onReset={resetTransactionFilters}
                onSave={setTransactionSaveRequest}
                saveResult={transactionSaveResult}
                screen={transactionScreen}
              />
            </div>
          )
        ) : overviewError ? (
          <main><OutputError message={overviewError.message} /></main>
        ) : !overview ? (
          <main><LoadingPanel label="Loading your budget…" /></main>
        ) : (
          <div className={overviewStatus === "recalculating" ? "recalculating" : ""}>
            <OverviewView
              overview={overview}
              onMonthChange={changeMonth}
              onSelectCategory={openCategory}
            />
          </div>
        )}
      </div>

      <footer>
        <span>A Choco Trail project</span>
        <img alt="Choco Trail" src="brand/logo/svg/choco-trail-lockup-horizontal-ink-outlined.svg" />
      </footer>
    </div>
  );
}
