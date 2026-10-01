import type { ComponentProps } from "react";

import { cn } from "#helpers/cn.utils";

export type CardDescriptionProps = ComponentProps<"p">;

export function CardDescription({ className, ...descriptionProps }: CardDescriptionProps) {
  return (
    <p
      data-slot="card-description"
      className={cn("text-sm text-muted-foreground", className)}
      {...descriptionProps}
    />
  );
}
