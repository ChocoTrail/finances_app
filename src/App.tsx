import type { ChangeEvent } from "react";

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

type EchoResponse = {
  acknowledged: boolean;
  message: string;
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
  const progress = Math.max(
    0,
    Math.min(100, (category.net_spending / category.monthly_allocation) * 100),
  );
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
      <span className="balance-label">
        {category.balance_state === "deficit" ? "Deficit" : "Available"}
      </span>
      <strong className="category-balance">{currency.format(category.available_balance)}</strong>
      <span className="spending-line">
        <span>{spendingText}</span>
        <span>{currency.format(category.monthly_allocation)} allocated</span>
      </span>
      <span className="progress-track" aria-hidden="true">
        <span style={{ width: `${progress}%` }} />
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
  return (
    <main>
      <section className="overview-heading" aria-labelledby="overview-title">
        <div>
          <p className="eyebrow">Overview</p>
          <h1 id="overview-title">Your rollover budget</h1>
          <p className="lede">Each category carries its own balance forward month to month.</p>
        </div>
        <MonthNavigation overview={overview} onChange={onMonthChange} />
      </section>

      <AccountFreshnessList accounts={overview.accounts} />

      <section aria-labelledby="categories-title">
        <div className="section-heading compact-heading">
          <div>
            <p className="eyebrow">Available by category</p>
            <h2 id="categories-title">{overview.month_label}</h2>
          </div>
          <p>Available includes this month’s allocation and all earlier rollover.</p>
        </div>
        <div className="category-grid">
          {overview.categories.map((category) => (
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

function PreviewPanel({ preview }: { preview: ImportPreview | null | undefined }) {
  const status = useShinyOutputStatus("import_preview");
  const error = useShinyOutputError("import_preview");

  if (error) return <OutputError message={error.message} />;

  if (!preview || preview.status === "waiting") {
    return (
      <div className="empty-state">
        <p className="empty-title">No file selected</p>
        <p>Choose an account export to test the supported upload path.</p>
      </div>
    );
  }

  if (preview.status === "error") {
    return <OutputError message={preview.message ?? "The preview failed."} />;
  }

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
    </div>
  );
}

function ImportPrototype({ account, echo, message, preview, setAccount, setMessage }: {
  account: Account;
  echo: EchoResponse | null | undefined;
  message: string;
  preview: ImportPreview | null | undefined;
  setAccount: (account: Account) => void;
  setMessage: (message: string) => void;
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
        <PreviewPanel preview={preview} />
      </section>

      <section className="panel bridge-panel" aria-labelledby="bridge-title">
        <div>
          <p className="eyebrow">JSON exchange</p>
          <h2 id="bridge-title">Client/server check</h2>
          <p>This text crosses the ShinyReact bridge and returns as structured JSON.</p>
        </div>
        <label className="text-field">
          <span>Message</span>
          <input
            onChange={(event: ChangeEvent<HTMLInputElement>) => setMessage(event.target.value)}
            type="text"
            value={message}
          />
        </label>
        <div className="echo" aria-live="polite">
          <span>R server</span>
          <strong>{echo?.acknowledged ? echo.message : "Waiting for the server…"}</strong>
        </div>
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
  const [account, setAccount] = useShinyInput<Account>("account_slot", "checking", { debounceMs: 0 });
  const [message, setMessage] = useShinyInput("prototype_message", "Hello from React", { debounceMs: 0 });
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
  const echo = useShinyOutputValue<EchoResponse | null>("prototype_echo", null);

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
            aria-current={view === "transactions" ? "page" : undefined}
            onClick={openTransactionHistory}
            type="button"
          >
            Transactions
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

      {view === "admin" ? (
        configurationError ? <main><OutputError message={configurationError.message} /></main>
        : !configurationScreen ? <main><LoadingPanel label="Loading configuration…" /></main>
        : <div className={configurationStatus === "recalculating" ? "recalculating" : ""}>
          <AdminView
            screen={configurationScreen}
            saveResult={configurationSaveResult ?? null}
            onSave={setConfigurationSaveRequest}
            importContent={<ImportPrototype account={account} echo={echo} message={message} preview={preview} setAccount={setAccount} setMessage={setMessage} />}
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

      <footer>
        <span>A Choco Trail project</span>
        <img alt="Choco Trail" src="brand/logo/svg/choco-trail-lockup-horizontal-ink-outlined.svg" />
      </footer>
    </div>
  );
}
