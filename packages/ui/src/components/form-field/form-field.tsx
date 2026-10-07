import { useId, type ComponentProps } from "react";

import { cn } from "#helpers/cn.utils";
import { Icon } from "#icons/icon";
import { Input } from "#primitives/input/input";
import { Label } from "#primitives/label/label";

export type FormFieldProps = Omit<ComponentProps<typeof Input>, "id"> & {
  label: string;
  /** Help shown under the field and linked to it for screen readers. */
  hint?: string;
  /** Validation message shown next to the field. An empty value hides it. */
  error?: string | undefined;
  id?: string;
};

/** A labelled input with optional hint and inline error, wired together for assistive technology. */
export function FormField({ label, hint, error, id, className, ...inputProps }: FormFieldProps) {
  const generatedId = useId();
  const fieldId = id ?? generatedId;
  const hintId = `${fieldId}-hint`;
  const errorId = `${fieldId}-error`;
  const hasError = error !== undefined && error !== "";
  const describedBy = [hint ? hintId : null, hasError ? errorId : null].filter(Boolean).join(" ");

  return (
    <div data-slot="form-field" className="flex flex-col gap-2">
      <Label htmlFor={fieldId}>{label}</Label>
      <Input
        id={fieldId}
        aria-invalid={hasError}
        aria-describedby={describedBy === "" ? undefined : describedBy}
        className={cn(className)}
        {...inputProps}
      />
      {hint ? (
        <p id={hintId} className="text-sm text-muted-foreground">
          {hint}
        </p>
      ) : null}
      <p id={errorId} aria-live="polite" className="text-sm text-destructive-text empty:hidden">
        {hasError ? (
          <span className="flex items-start gap-2">
            <Icon name="circle-alert" className="mt-0.5" />
            <span>{error}</span>
          </span>
        ) : null}
      </p>
    </div>
  );
}
