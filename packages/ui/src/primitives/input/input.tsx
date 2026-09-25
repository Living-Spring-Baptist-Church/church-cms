import type { ComponentProps } from "react";

import { cn } from "#helpers/cn.utils";

export type InputProps = ComponentProps<"input">;

export function Input({ className, type = "text", ...inputProps }: InputProps) {
  return (
    <input
      data-slot="input"
      type={type}
      className={cn(
        "flex h-11 w-full min-w-0 rounded-md border border-input bg-background px-3 text-base text-foreground placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-2 focus-visible:ring-ring focus-visible:outline-none disabled:cursor-not-allowed disabled:opacity-50 aria-invalid:border-destructive md:text-sm",
        className,
      )}
      {...inputProps}
    />
  );
}
