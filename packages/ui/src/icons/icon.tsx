import { Check, CircleAlert, Copy, Info, LogOut, ShieldCheck } from "lucide-react";
import type { ComponentProps } from "react";

import { cn } from "#helpers/cn.utils";

const ICONS = {
  check: Check,
  "circle-alert": CircleAlert,
  copy: Copy,
  info: Info,
  "log-out": LogOut,
  "shield-check": ShieldCheck,
} as const;

export type IconName = keyof typeof ICONS;

export type IconProps = Omit<ComponentProps<"svg">, "children"> & {
  name: IconName;
};

/** The one icon entry point. Icons are decorative: put the meaning in text beside them. */
export function Icon({ name, className, ...svgProps }: IconProps) {
  const IconComponent = ICONS[name];
  return (
    <IconComponent
      data-slot="icon"
      aria-hidden="true"
      focusable="false"
      className={cn("size-4 shrink-0", className)}
      {...svgProps}
    />
  );
}
