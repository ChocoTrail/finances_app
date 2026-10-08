import type { ChangeEvent } from "react";

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

function Metric({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="metric">
      <dt>{label}</dt>
      <dd>{value}</dd>
    </div>
  );
}

function PreviewPanel({ preview }: { preview: ImportPreview | null | undefined }) {
  const status = useShinyOutputStatus("import_preview");
  const error = useShinyOutputError("import_preview");

  if (error) {
    return (
      <div className="notice notice-error" role="alert">
        <strong>Preview failed.</strong> {error.message}
      </div>
    );
  }

  if (!preview || preview.status === "waiting") {
    return (
      <div className="empty-state">
        <p className="empty-title">No file selected</p>
        <p>Choose an account export to test the supported upload path.</p>
      </div>
    );
  }

  if (preview.status === "error") {
    return (
      <div className="notice notice-error" role="alert">
        <strong>Preview failed.</strong> {preview.message}
      </div>
    );
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

export default function App() {
  const initialized = useShinyInitialized();
  const busy = useShinyBusy();
  const [account, setAccount] = useShinyInput<Account>("account_slot", "checking", {
    debounceMs: 0,
  });
  const [message, setMessage] = useShinyInput("prototype_message", "Hello from React", {
    debounceMs: 0,
  });
  const preview = useShinyOutputValue<ImportPreview | null>("import_preview", null);
  const echo = useShinyOutputValue<EchoResponse | null>("prototype_echo", null);

  if (!initialized) return null;

  return (
    <div className={busy ? "app-shell busy" : "app-shell"}>
      <div className="activity-line" aria-hidden="true" />
      <header className="site-header">
        <div>
          <p className="eyebrow">Technical prototype</p>
          <h1>Family finances</h1>
          <p className="lede">
            A first connection between the React interface and the R financial rules.
          </p>
        </div>
        <span className="prototype-tag">Upload + JSON bridge</span>
      </header>

      <main>
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
      </main>

      <footer>
        <span>A Choco Trail project</span>
        <img
          alt="Choco Trail"
          src="brand/logo/svg/choco-trail-lockup-horizontal-ink-outlined.svg"
        />
      </footer>
    </div>
  );
}
