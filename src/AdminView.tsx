import type { FormEvent, ReactNode } from "react";

const { React } = window.shinyreact;

type CategoryOption = { value: string; label: string; sort_order: number };
type Merchant = {
  display_name: string;
  category_code: string;
};
type MerchantDefault = { display_name: string; first_seen_date: string; category_code: string | null };
type Allocation = { category_code: string; category: string; amount: number };
type BudgetVersion = {
  budget_version_id: string;
  effective_month: string;
  total_monthly_budget: number;
  allocations: Allocation[];
};

export type ConfigurationScreen = {
  status: "ready";
  current_month: string;
  default_effective_month: string;
  categories: CategoryOption[];
  merchants: Merchant[];
  merchant_defaults: MerchantDefault[];
  new_merchants: MerchantDefault[];
  budget_versions: BudgetVersion[];
  budget_setup: { budget_start_month: string | null };
};

export type ConfigurationSaveResult = {
  status: "idle" | "saved" | "already_saved" | "error";
  request_id?: string;
  message?: string;
  matched_transaction_count?: number;
};

export type ConfigurationSaveRequest = Record<string, unknown>;
type Section = "import" | "merchants" | "budget" | "rollover";

const money = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" });
const monthLabel = new Intl.DateTimeFormat("en-US", { month: "long", year: "numeric", timeZone: "UTC" });
const requestId = (kind: string) => `${kind}-${crypto.randomUUID()}`;
const formatMonth = (value: string) => monthLabel.format(new Date(`${value}T00:00:00Z`));

function SaveNotice({ result }: { result: ConfigurationSaveResult | null }) {
  if (!result || result.status === "idle") return null;
  if (result.status === "error") {
    return <div className="notice notice-error" role="alert"><strong>Nothing was saved.</strong> {result.message}</div>;
  }
  const suffix = result.matched_transaction_count
    ? ` ${result.matched_transaction_count} existing transaction${result.matched_transaction_count === 1 ? " was" : "s were"} updated.`
    : "";
  return <div className="notice notice-success" role="status">
    {result.status === "already_saved" ? "This request was already saved." : `Changes saved.${suffix}`}
  </div>;
}

function MerchantAdmin({ screen, onSave, result }: {
  screen: ConfigurationScreen;
  onSave: (request: ConfigurationSaveRequest) => void;
  result: ConfigurationSaveResult | null;
}) {
  const [search, setSearch] = React.useState("");
  const [pendingKey, setPendingKey] = React.useState<string | null>(null);
  const [submittedRequestId, setSubmittedRequestId] = React.useState<string | null>(null);
  const [choices, setChoices] = React.useState<Record<string, string>>({});
  const categoryOrder = ["food_living", "personal_discretionary", "transportation", "housing"];
  const categoryChoices = categoryOrder
    .map((value) => screen.categories.find((category) => category.value === value))
    .filter((category): category is CategoryOption => Boolean(category));
  const shortCategoryLabels: Record<string, string> = {
    food_living: "Food & Living",
    personal_discretionary: "Personal",
    transportation: "Transportation",
    housing: "Housing",
  };
  const filtered = [...screen.merchant_defaults]
    .sort((a, b) => a.display_name.localeCompare(b.display_name))
    .filter((merchant) => merchant.display_name.toLowerCase().includes(search.trim().toLowerCase()));
  const matchingResult = result?.request_id === submittedRequestId ? result : null;

  React.useEffect(() => {
    if (matchingResult) setPendingKey(null);
  }, [matchingResult]);

  const saveChoice = (key: string, categoryCode: string, details: Record<string, unknown>) => {
    const nextRequestId = requestId("merchant");
    setChoices((current) => ({ ...current, [key]: categoryCode }));
    setPendingKey(key);
    setSubmittedRequestId(nextRequestId);
    onSave({ kind: "merchant_default", request_id: nextRequestId, category_code: categoryCode, ...details });
  };

  const radioRow = (key: string, name: string, currentCategory: string | null, details: Record<string, unknown>, note?: string) => {
    const selectedCategory = choices[key] ?? currentCategory;
    return <div className="merchant-default-row" key={key}>
      <div className="merchant-default-name"><strong>{name}</strong>{note && <small>{note}</small>}</div>
      <fieldset aria-label={`Default category for ${name}`} disabled={pendingKey === key}>
        {categoryChoices.map((category) => <label key={category.value}>
          <input checked={selectedCategory === category.value} name={`merchant-${key}`} onChange={() => saveChoice(key, category.value, details)} type="radio" />
          <span>{shortCategoryLabels[category.value] ?? category.label}</span>
        </label>)}
      </fieldset>
      {pendingKey === key && <span className="inline-saving" role="status">Saving…</span>}
    </div>;
  };

  return <section className="merchant-defaults" aria-labelledby="merchant-admin-title">
    <div className="panel merchant-new-panel">
      <div><p className="eyebrow">Recently seen</p><h2>New since last month</h2><p>These merchants first appeared since the start of last month.</p></div>
      {screen.new_merchants.length
        ? <div className="merchant-default-list">{screen.new_merchants.map((merchant) => radioRow(
          `new-${merchant.display_name}`, merchant.display_name, merchant.category_code,
          { merchant_description: merchant.display_name },
          `${merchant.category_code === "rainy_day" ? "Assign Rainy Day individually · " : !merchant.category_code ? "Choose a default · " : ""}First seen ${formatMonth(`${merchant.first_seen_date.slice(0, 7)}-01`)}`,
        ))}</div>
        : <p className="empty-list-message">No new merchants need a default.</p>}
    </div>
    <div className="panel admin-list-panel">
      <div><p className="eyebrow">Future imports</p><h2 id="merchant-admin-title">All merchant defaults</h2><p>Choose what each merchant should use going forward. Past transactions will not change.</p></div>
      <label className="text-field"><span>Search merchants</span><input value={search} onChange={(event) => setSearch(event.target.value)} type="search" /></label>
      <div className="merchant-default-list">
        {filtered.map((merchant) => radioRow(
          `all-${merchant.display_name}`, merchant.display_name, merchant.category_code,
          { merchant_description: merchant.display_name },
          merchant.category_code === "rainy_day" ? "Assign Rainy Day to individual transactions" : !merchant.category_code ? "Choose a default" : undefined,
        ))}
        {!filtered.length && <p className="empty-list-message">No merchants match that search.</p>}
      </div>
      <SaveNotice result={matchingResult} />
    </div>
  </section>;
}

function BudgetAdmin({ screen, onSave, result }: {
  screen: ConfigurationScreen; onSave: (request: ConfigurationSaveRequest) => void; result: ConfigurationSaveResult | null;
}) {
  const latest = screen.budget_versions[screen.budget_versions.length - 1];
  const initialAmounts = Object.fromEntries(screen.categories.map((category) => [category.value,
    latest?.allocations.find((item) => item.category_code === category.value)?.amount ?? 0]));
  const [effectiveMonth, setEffectiveMonth] = React.useState(screen.default_effective_month);
  const [amounts, setAmounts] = React.useState<Record<string, number>>(initialAmounts);
  const [submittedRequestId, setSubmittedRequestId] = React.useState<string | null>(null);
  const total = Object.values(amounts).reduce((sum, amount) => sum + Number(amount || 0), 0);
  const submit = (event: FormEvent) => {
    event.preventDefault();
    const nextRequestId = requestId("budget");
    setSubmittedRequestId(nextRequestId);
    onSave({ kind: "budget_version", request_id: nextRequestId, effective_month: effectiveMonth,
      total_monthly_budget: total, allocations: screen.categories.map((category) => ({ category_code: category.value, amount: Number(amounts[category.value]) })) });
  };
  const matchingResult = result?.request_id === submittedRequestId ? result : null;
  const isSaving = Boolean(submittedRequestId) && !matchingResult;
  return <div className="admin-grid">
    <form className="panel admin-form" onSubmit={submit}>
      <div><p className="eyebrow">New version</p><h2>Monthly budget</h2><p>Defaults to next month. You may choose the current month, but prior months stay unchanged.</p></div>
      <label className="text-field"><span>Effective month</span><input type="month" required min={screen.current_month.slice(0, 7)} value={effectiveMonth.slice(0, 7)} onChange={(e) => setEffectiveMonth(`${e.target.value}-01`)} /></label>
      <div className="allocation-fields">{screen.categories.map((category) => <label className="text-field" key={category.value}><span>{category.label}</span>
        <input min="0" step="0.01" type="number" value={amounts[category.value]} onChange={(e) => setAmounts({ ...amounts, [category.value]: Number(e.target.value) })} /></label>)}</div>
      <div className="budget-total"><span>Monthly total</span><strong>{money.format(total)}</strong></div>
      <SaveNotice result={matchingResult} />
      <button className="primary-button" disabled={isSaving} type="submit">{isSaving ? "Saving…" : "Create budget version"}</button>
    </form>
    <section className="panel"><p className="eyebrow">History</p><h2>Budget versions</h2><div className="version-list">
      {[...screen.budget_versions].reverse().map((version) => <details key={version.budget_version_id}><summary><span>{formatMonth(version.effective_month)}</span><strong>{money.format(version.total_monthly_budget)}</strong></summary>
        <ul>{version.allocations.map((allocation) => <li key={allocation.category_code}><span>{allocation.category}</span><strong>{money.format(allocation.amount)}</strong></li>)}</ul></details>)}
    </div></section>
  </div>;
}

function RolloverAdmin({ screen, onSave, result }: {
  screen: ConfigurationScreen; onSave: (request: ConfigurationSaveRequest) => void; result: ConfigurationSaveResult | null;
}) {
  const earliestBudgetMonth = screen.budget_versions
    .map((version) => version.effective_month)
    .sort()[0]
    ?.slice(0, 7);
  const [startMonth, setStartMonth] = React.useState((screen.budget_setup.budget_start_month ?? screen.current_month).slice(0, 7));
  const [submittedRequestId, setSubmittedRequestId] = React.useState<string | null>(null);
  const submit = (event: FormEvent) => {
    event.preventDefault();
    const nextRequestId = requestId("rollover");
    setSubmittedRequestId(nextRequestId);
    onSave({ kind: "rollover_start", request_id: nextRequestId, budget_start_month: `${startMonth}-01` });
  };
  const matchingResult = result?.request_id === submittedRequestId ? result : null;
  const isSaving = Boolean(submittedRequestId) && !matchingResult;
  return <form className="panel admin-form setup-form" onSubmit={submit}>
    <div><p className="eyebrow">Rollover settings</p><h2>Choose when rollover begins</h2><p>The start month is the earliest month shown in Overview. Every later month carries its remaining balance forward from this point.</p></div>
    <label className="text-field"><span>Rollover start month</span><input max={screen.current_month.slice(0, 7)} min={earliestBudgetMonth} required type="month" value={startMonth} onChange={(e) => setStartMonth(e.target.value)} /></label>
    <div className="notice notice-warning"><strong>Changing the start month recalculates later rollover balances.</strong> It does not change transactions or monthly budget versions.</div>
    <p className="field-help">The selected month must have a monthly budget version in effect.</p>
    <SaveNotice result={matchingResult} />
    <button className="primary-button" disabled={isSaving} type="submit">{isSaving ? "Saving…" : "Save rollover settings"}</button>
  </form>;
}

export default function AdminView({ screen, saveResult, onSave, importContent }: {
  screen: ConfigurationScreen;
  saveResult: ConfigurationSaveResult | null;
  onSave: (request: ConfigurationSaveRequest) => void;
  importContent: ReactNode;
}) {
  const [section, setSection] = React.useState<Section>("import");
  return <main>
    <section className="overview-heading"><div><p className="eyebrow">Configuration</p><h1>Admin</h1><p className="lede">Manage imports, merchant defaults, monthly budgets, and when rollover tracking begins.</p></div></section>
    <nav className="admin-nav" aria-label="Admin sections">
      {([['import', 'Import'], ['merchants', 'Merchant defaults'], ['budget', 'Monthly budget'], ['rollover', 'Rollover']] as Array<[Section, string]>).map(([value, label]) =>
        <button aria-current={section === value ? "page" : undefined} key={value} onClick={() => setSection(value)} type="button">{label}</button>)}
    </nav>
    {section === "import" ? importContent : section === "merchants" ? <MerchantAdmin screen={screen} onSave={onSave} result={saveResult} />
      : section === "budget" ? <BudgetAdmin screen={screen} onSave={onSave} result={saveResult} />
      : <RolloverAdmin screen={screen} onSave={onSave} result={saveResult} />}
  </main>;
}
