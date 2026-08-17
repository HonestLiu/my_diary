import { Component, type ErrorInfo, type ReactNode } from "react";
import { logger } from "@/lib/logger";

interface Props {
  children: ReactNode;
  fallback?: ReactNode;
}

interface State {
  error: Error | null;
}

/**
 * Catches render-time errors anywhere in the tree so a single broken component
 * can't blank the entire app. Logs the error locally (never exfiltrated) and
 * offers a recover button.
 */
export class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo): void {
    logger.error("Uncaught UI error", error, info.componentStack ?? "");
  }

  render(): ReactNode {
    const { error } = this.state;
    if (error) {
      if (this.props.fallback) return this.props.fallback;
      return (
        <div className="flex h-full w-full flex-col items-center justify-center gap-3 p-8 text-center">
          <h1 className="text-lg font-semibold">出错了</h1>
          <p className="max-w-md text-sm text-muted-foreground">{error.message}</p>
          <button
            type="button"
            className="rounded-md border border-border px-3 py-1.5 text-sm transition-colors hover:bg-muted"
            onClick={() => this.setState({ error: null })}
          >
            重试
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}
