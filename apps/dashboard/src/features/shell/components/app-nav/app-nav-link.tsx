"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

import { cn } from "@lbc/ui";

import { isRouteActive } from "@helpers/navigation.utils";

export type AppNavLinkProps = {
  href: string;
  label: string;
};

const LINK_BASE_CLASS_NAME =
  "inline-flex min-h-11 items-center rounded-md px-3 text-sm font-medium underline-offset-4 hover:underline focus-visible:ring-2 focus-visible:ring-ring focus-visible:outline-none";
const CURRENT_CLASS_NAME = "bg-brand text-brand-foreground hover:no-underline";

/** A navigation link that marks the current module for keyboard and screen reader users. */
export function AppNavLink({ href, label }: AppNavLinkProps) {
  const pathname = usePathname();
  const isCurrent = isRouteActive(pathname, href);
  return (
    <Link
      href={href}
      aria-current={isCurrent ? "page" : undefined}
      className={cn(LINK_BASE_CLASS_NAME, isCurrent && CURRENT_CLASS_NAME)}
    >
      {label}
    </Link>
  );
}
