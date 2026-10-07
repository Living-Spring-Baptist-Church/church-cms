import { cva, type VariantProps } from "class-variance-authority";
import type { ComponentProps } from "react";

import { cn } from "#helpers/cn.utils";
import { Icon, type IconName } from "#icons/icon";

export const alertVariants = cva("flex items-start gap-3 rounded-md border p-3 text-sm", {
  variants: {
    variant: {
      destructive: "border-destructive bg-background text-destructive-text",
      info: "border-info bg-info-surface text-foreground",
      success: "border-success bg-success-surface text-foreground",
    },
  },
  defaultVariants: { variant: "info" },
});

const ALERT_ICONS: Readonly<
  Record<NonNullable<VariantProps<typeof alertVariants>["variant"]>, IconName>
> = {
  destructive: "circle-alert",
  info: "info",
  success: "check",
};

export type AlertProps = ComponentProps<"div"> & VariantProps<typeof alertVariants>;

/**
 * A message with an icon, so meaning never rests on colour alone. Pass role="alert" for a failure
 * that must be announced at once, or role="status" for a calm update.
 */
export function Alert({ className, variant, children, ...alertProps }: AlertProps) {
  return (
    <div data-slot="alert" className={cn(alertVariants({ variant }), className)} {...alertProps}>
      <Icon name={ALERT_ICONS[variant ?? "info"]} className="mt-0.5" />
      <div className="min-w-0 flex-1">{children}</div>
    </div>
  );
}
