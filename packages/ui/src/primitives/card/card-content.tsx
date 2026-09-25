import type { ComponentProps } from "react";

import { cn } from "#helpers/cn.utils";

export type CardContentProps = ComponentProps<"div">;

export function CardContent({ className, ...contentProps }: CardContentProps) {
  return <div data-slot="card-content" className={cn("px-6", className)} {...contentProps} />;
}
