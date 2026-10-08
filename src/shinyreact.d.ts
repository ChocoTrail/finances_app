import type * as ReactTypes from "react";
import type { Root } from "react-dom/client";

type ShinyOutputStatus = "pending" | "ready" | "recalculating" | "error";

type ShinyInputOptions = {
  debounceMs?: number;
  priority?: "event" | "deferred";
  type?: string;
};

type ShinyOutputError = {
  message: string;
  call?: string;
  type?: string;
};

type ShinyOutputProps = ReactTypes.HTMLAttributes<HTMLElement> & {
  id: string;
  tagName?: string;
  namespace?: string | null;
};

interface ShinyReactGlobal {
  React: typeof ReactTypes;
  ReactDOM: {
    createRoot(container: Element | DocumentFragment): Root;
  };
  ShinyOutput: ReactTypes.ComponentType<ShinyOutputProps>;
  useShinyInitialized(): boolean;
  useShinyBusy(): boolean;
  useShinyInput<T>(
    id: string,
    defaultValue: T,
    options?: ShinyInputOptions,
  ): [T, ReactTypes.Dispatch<ReactTypes.SetStateAction<T>>];
  useShinyOutputValue<T>(id: string, defaultValue?: T): T | undefined;
  useShinyOutputStatus(id: string): ShinyOutputStatus;
  useShinyOutputError(id: string): ShinyOutputError | null;
}

declare global {
  interface Window {
    shinyreact: ShinyReactGlobal;
  }
}

export {};
