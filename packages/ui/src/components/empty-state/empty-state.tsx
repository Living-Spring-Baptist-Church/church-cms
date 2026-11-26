import type { ReactNode } from "react";

export type EmptyStateProps = {
  /** Plain text that says what is missing, for example "No Sunday service has been recorded yet." */
  message: string;
  /** An optional next step, such as a link that adds the first record. */
  children?: ReactNode;
};

/** Shown when a screen loads fine but there is nothing to list yet. */
export function EmptyState({ message, children }: EmptyStateProps) {
  return (
    <div
      data-slot="empty-state"
      className="flex flex-col gap-3 rounded-md border border-dashed border-border p-4 text-sm text-muted-foreground"
    >
      <p>{message}</p>
      {children}
    </div>
  );
}
