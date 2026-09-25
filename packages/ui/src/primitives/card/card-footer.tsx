import type { ComponentProps } from "react";

import { cn } from "#helpers/cn.utils";

export type CardFooterProps = ComponentProps<"div">;

export function CardFooter({ className, ...footerProps }: CardFooterProps) {
  return (
    <div
      data-slot="card-footer"
      className={cn("flex flex-wrap items-center gap-3 px-6", className)}
      {...footerProps}
    />
  );
}
