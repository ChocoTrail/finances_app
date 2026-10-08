import type { FormEvent, ReactNode } from "react";

const { React } = window.shinyreact;

type CategoryOption = { value: string; label: string; sort_order: number };
type Merchant = {
  rule_id: string;
  display_name: string;
  description_pattern: string;
  category_code: string;
  effective_date: string;
  priority: number;
  is_active: boolean;
};
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
  budget_versions: BudgetVersion[];
  budget_setup: { budget_start_month: string | null; opening_balances: Allocation[] };
};

export type ConfigurationSaveResult = {
  status: "idle" | "saved" | "already_saved" | "error";
  request_id?: string;
  message?: string;
  matched_transaction_count?: number;
};

export type ConfigurationSaveRequest = Record<string, unknown>;
type Section = "import" | "merchants" | "budget" | "setup";

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
  const [selected, setSelected] = React.useState<Merchant | null>(null);
  const [form, setForm] = React.useState({
    display_name: "", description_pattern: "", category_code: screen.categories[0]?.value ?? "",
    effective_date: new Date().toISOString().slice(0, 10), is_active: true, apply_existing: false,
  });
  const filtered = screen.merchants.filter((merchant) =>
    `${merchant.display_name} ${merchant.description_pattern}`.toLowerCase().includes(search.toLowerCase()),
  );
  const startNew = () => {
    setSelected(null);
    setForm({ display_name: "", description_pattern: "", category_code: screen.categories[0]?.value ?? "",
      effective_date: new Date().toISOString().slice(0, 10), is_active: true, apply_existing: false });
  };
  const edit = (merchant: Merchant) => {
    setSelected(merchant);
    setForm({ display_name: merchant.display_name, description_pattern: merchant.description_pattern,
      category_code: merchant.category_code, effective_date: merchant.effective_date,
      is_active: merchant.is_active, apply_existing: false });
  };
  const submit = (event: FormEvent) => {
    event.preventDefault();
    onSave({ kind: "merchant", request_id: requestId("merchant"), rule_id: selected?.rule_id ?? null, ...form });
  };

  return <section className="admin-grid" aria-labelledby="merchant-admin-title">
    <div className="panel admin-list-panel">
      <div className="section-heading"><div><p className="eyebrow">Matching rules</p><h2 id="merchant-admin-title">Merchant defaults</h2></div>
        <button className="secondary-button" onClick={startNew} type="button">New merchant</button></div>
      <label className="text-field"><span>Search merchants</span><input value={search} onChange={(event) => setSearch(event.target.value)} type="search" /></label>
      <div className="merchant-list">
        {filtered.map((merchant) => <button className={selected?.rule_id === merchant.rule_id ? "merchant-item selected" : "merchant-item"}
          key={merchant.rule_id} onClick={() => edit(merchant)} type="button">
          <span><strong>{merchant.display_name}</strong><small>{screen.categories.find((item) => item.value === merchant.category_code)?.label}</small></span>
          <span className={merchant.is_active ? "status status-ready" : "status"}>{merchant.is_active ? "Active" : "Inactive"}</span>
        </button>)}
      </div>
    </div>
    <form className="panel admin-form" onSubmit={submit}>
      <div><p className="eyebrow">{selected ? "Edit default" : "Create default"}</p><h2>{selected?.display_name ?? "New merchant"}</h2></div>
      <label className="text-field"><span>Display name</span><input required maxLength={100} value={form.display_name} onChange={(e) => setForm({ ...form, display_name: e.target.value })} /></label>
      <label className="text-field"><span>Description regular expression</span><input required value={form.description_pattern} onChange={(e) => setForm({ ...form, description_pattern: e.target.value })} /></label>
      <label className="text-field"><span>Default category</span><select value={form.category_code} onChange={(e) => setForm({ ...form, category_code: e.target.value })}>
        {screen.categories.map((category) => <option value={category.value} key={category.value}>{category.label}</option>)}</select></label>
      <label className="text-field"><span>Effective date</span><input type="date" required value={form.effective_date} onChange={(e) => setForm({ ...form, effective_date: e.target.value })} /></label>
      <label className="check-field"><input type="checkbox" checked={form.is_active} onChange={(e) => setForm({ ...form, is_active: e.target.checked, apply_existing: e.target.checked ? form.apply_existing : false })} /><span>Active for future imports</span></label>
      <label className="check-field deliberate"><input type="checkbox" disabled={!form.is_active} checked={form.apply_existing} onChange={(e) => setForm({ ...form, apply_existing: e.target.checked })} /><span>Also apply this rule to matching existing transactions</span></label>
      <p className="field-help">Existing transactions stay unchanged unless you deliberately select the option above. Rules can be deactivated, not deleted.</p>
      <SaveNotice result={result} />
      <button className="primary-button" type="submit">Save merchant default</button>
    </form>
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
  const total = Object.values(amounts).reduce((sum, amount) => sum + Number(amount || 0), 0);
  const submit = (event: FormEvent) => {
    event.preventDefault();
    onSave({ kind: "budget_version", request_id: requestId("budget"), effective_month: effectiveMonth,
      total_monthly_budget: total, allocations: screen.categories.map((category) => ({ category_code: category.value, amount: Number(amounts[category.value]) })) });
  };
  return <div className="admin-grid">
    <form className="panel admin-form" onSubmit={submit}>
      <div><p className="eyebrow">New version</p><h2>Monthly budget</h2><p>Defaults to next month. You may choose the current month, but prior months stay unchanged.</p></div>
      <label className="text-field"><span>Effective month</span><input type="month" required min={screen.current_month.slice(0, 7)} value={effectiveMonth.slice(0, 7)} onChange={(e) => setEffectiveMonth(`${e.target.value}-01`)} /></label>
      <div className="allocation-fields">{screen.categories.map((category) => <label className="text-field" key={category.value}><span>{category.label}</span>
        <input min="0" step="0.01" type="number" value={amounts[category.value]} onChange={(e) => setAmounts({ ...amounts, [category.value]: Number(e.target.value) })} /></label>)}</div>
      <div className="budget-total"><span>Monthly total</span><strong>{money.format(total)}</strong></div>
      <SaveNotice result={result} />
      <button className="primary-button" type="submit">Create budget version</button>
    </form>
    <section className="panel"><p className="eyebrow">History</p><h2>Budget versions</h2><div className="version-list">
      {[...screen.budget_versions].reverse().map((version) => <details key={version.budget_version_id}><summary><span>{formatMonth(version.effective_month)}</span><strong>{money.format(version.total_monthly_budget)}</strong></summary>
        <ul>{version.allocations.map((allocation) => <li key={allocation.category_code}><span>{allocation.category}</span><strong>{money.format(allocation.amount)}</strong></li>)}</ul></details>)}
    </div></section>
  </div>;
}

function SetupAdmin({ screen, onSave, result }: {
  screen: ConfigurationScreen; onSave: (request: ConfigurationSaveRequest) => void; result: ConfigurationSaveResult | null;
}) {
  const [startMonth, setStartMonth] = React.useState((screen.budget_setup.budget_start_month ?? screen.current_month).slice(0, 7));
  const [amounts, setAmounts] = React.useState<Record<string, number>>(Object.fromEntries(screen.categories.map((category) => [category.value,
    screen.budget_setup.opening_balances.find((item) => item.category_code === category.value)?.amount ?? 0])));
  const submit = (event: FormEvent) => {
    event.preventDefault();
    onSave({ kind: "opening_balances", request_id: requestId("opening"), budget_start_month: `${startMonth}-01`,
      opening_balances: screen.categories.map((category) => ({ category_code: category.value, amount: Number(amounts[category.value]) })) });
  };
  return <form className="panel admin-form setup-form" onSubmit={submit}>
    <div><p className="eyebrow">Rollover foundation</p><h2>Budget start and opening balances</h2><p>These five balances establish the amount carried into the first configured budget month.</p></div>
    <label className="text-field"><span>Budget start month</span><input max={screen.current_month.slice(0, 7)} required type="month" value={startMonth} onChange={(e) => setStartMonth(e.target.value)} /></label>
    <div className="allocation-fields">{screen.categories.map((category) => <label className="text-field" key={category.value}><span>{category.label}</span>
      <input step="0.01" type="number" value={amounts[category.value]} onChange={(e) => setAmounts({ ...amounts, [category.value]: Number(e.target.value) })} /></label>)}</div>
    <p className="field-help">Opening balances may be negative. The selected month must already have an effective budget version.</p>
    <SaveNotice result={result} />
    <button className="primary-button" type="submit">Save budget setup</button>
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
    <section className="overview-heading"><div><p className="eyebrow">Configuration</p><h1>Admin</h1><p className="lede">Manage imports, merchant defaults, and the rollover budget foundation.</p></div></section>
    <nav className="admin-nav" aria-label="Admin sections">
      {([['import', 'Import'], ['merchants', 'Merchant defaults'], ['budget', 'Monthly budget'], ['setup', 'Budget setup']] as Array<[Section, string]>).map(([value, label]) =>
        <button aria-current={section === value ? "page" : undefined} key={value} onClick={() => setSection(value)} type="button">{label}</button>)}
    </nav>
    {section === "import" ? importContent : section === "merchants" ? <MerchantAdmin screen={screen} onSave={onSave} result={saveResult} />
      : section === "budget" ? <BudgetAdmin screen={screen} onSave={onSave} result={saveResult} />
      : <SetupAdmin screen={screen} onSave={onSave} result={saveResult} />}
  </main>;
}
