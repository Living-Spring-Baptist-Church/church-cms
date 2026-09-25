import type { ComponentProps } from "react";

import { cn } from "#helpers/cn.utils";

export type CardProps = ComponentProps<"div">;

export function Card({ className, ...cardProps }: CardProps) {
  return (
    <div
      data-slot="card"
      className={cn(
        "flex flex-col gap-6 rounded-lg border border-border bg-card py-6 text-card-foreground shadow-sm",
        className,
      )}
      {...cardProps}
    />
  );
}
