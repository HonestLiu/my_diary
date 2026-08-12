/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** Local log verbosity: debug | info | warn | error. Optional. */
  readonly VITE_LOG_LEVEL?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
