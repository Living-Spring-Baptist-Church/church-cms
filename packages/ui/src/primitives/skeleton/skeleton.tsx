import type { ComponentProps } from "react";

import { cn } from "#helpers/cn.utils";

export type SkeletonProps = ComponentProps<"div">;

/** A placeholder that mirrors the shape of content that is still loading. Size it with classes. */
export function Skeleton({ className, ...skeletonProps }: SkeletonProps) {
  return (
    <div
      data-slot="skeleton"
      aria-hidden="true"
      className={cn("rounded-md bg-muted motion-safe:animate-pulse", className)}
      {...skeletonProps}
    />
  );
}
