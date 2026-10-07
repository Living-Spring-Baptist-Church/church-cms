import type { ComponentProps } from "react";

import { cn } from "#helpers/cn.utils";

export type LabelProps = ComponentProps<"label">;

export function Label({ className, ...labelProps }: LabelProps) {
  return (
    // The control is tied to the label through htmlFor, which the caller passes.
    // eslint-disable-next-line jsx-a11y/label-has-associated-control
    <label
      data-slot="label"
      className={cn("text-sm leading-none font-medium text-foreground", className)}
      {...labelProps}
    />
  );
}
