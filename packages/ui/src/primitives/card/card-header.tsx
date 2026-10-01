import type { ComponentProps } from "react";

import { cn } from "#helpers/cn.utils";

export type CardHeaderProps = ComponentProps<"div">;

export function CardHeader({ className, ...headerProps }: CardHeaderProps) {
  return (
    <div
      data-slot="card-header"
      className={cn("flex flex-col gap-2 px-6", className)}
      {...headerProps}
    />
  );
}
