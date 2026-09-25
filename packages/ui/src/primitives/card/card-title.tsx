import type { ComponentProps } from "react";

import { cn } from "#helpers/cn.utils";

type CardTitleElement = "h2" | "h3" | "h4";

export type CardTitleProps = ComponentProps<"h3"> & {
  /** Heading level that fits the page outline. Defaults to h3. */
  as?: CardTitleElement;
};

export function CardTitle({ as: HeadingElement = "h3", className, ...titleProps }: CardTitleProps) {
  return (
    <HeadingElement
      data-slot="card-title"
      className={cn("text-lg leading-tight font-semibold", className)}
      {...titleProps}
    />
  );
}
