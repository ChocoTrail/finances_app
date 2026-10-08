import "@/index.css";

import App from "@/App";

const { React, ReactDOM } = window.shinyreact;

const mount = document.body.appendChild(document.createElement("div"));
mount.id = "family-finances-root";

ReactDOM.createRoot(mount).render(<App />);
