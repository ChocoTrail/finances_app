import path from "node:path";
import { fileURLToPath } from "node:url";

import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

const projectDirectory = path.dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  define: {
    "process.env.NODE_ENV": JSON.stringify("production"),
  },
  plugins: [react({ jsxRuntime: "classic" })],
  resolve: {
    alias: { "@": path.resolve(projectDirectory, "src") },
  },
  build: {
    outDir: "www",
    emptyOutDir: false,
    cssCodeSplit: false,
    lib: {
      entry: path.resolve(projectDirectory, "src/ui.tsx"),
      formats: ["iife"],
      name: "FamilyFinances",
      fileName: () => "ui.js",
    },
    rollupOptions: {
      external: ["react", "react-dom", "react-dom/client"],
      output: {
        assetFileNames: "ui.[ext]",
        globals: {
          react: "window.shinyreact.React",
          "react-dom": "window.shinyreact.ReactDOM",
          "react-dom/client": "window.shinyreact.ReactDOM",
        },
      },
    },
  },
});
