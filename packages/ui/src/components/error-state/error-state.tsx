import type { ReactNode } from "react";

import { Alert } from "#primitives/alert/alert";
import { Button } from "#primitives/button/button";

export type ErrorStateProps = {
  title: string;
  /** A plain, actionable message. Never backend wording. */
  message: string;
  retryLabel: string;
  onRetry: () => void;
  children?: ReactNode;
};

/** Shown when a screen could not load or something unexpected failed, with a way to try again. */
export function ErrorState({ title, message, retryLabel, onRetry, children }: ErrorStateProps) {
  return (
    <section
      data-slot="error-state"
      aria-labelledby="error-state-title"
      className="flex flex-col gap-4"
    >
      <h1 id="error-state-title" className="text-2xl font-semibold text-primary">
        {title}
      </h1>
      <Alert variant="destructive" role="alert">
        {message}
      </Alert>
      <div className="flex flex-wrap gap-3">
        <Button onClick={onRetry}>{retryLabel}</Button>
        {children}
      </div>
    </section>
  );
}
