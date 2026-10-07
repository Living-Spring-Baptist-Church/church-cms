"use client";

import { useEffect, useRef } from "react";

import { CardTitle } from "@lbc/ui";

type StepHeadingProps = {
  heading: string;
  /** Move focus here when the screen appears, so a screen reader announces the new step. */
  shouldTakeFocus: boolean;
};

export function StepHeading({ heading, shouldTakeFocus }: StepHeadingProps) {
  const headingRef = useRef<HTMLHeadingElement>(null);

  useEffect(() => {
    if (shouldTakeFocus) {
      headingRef.current?.focus();
    }
  }, [shouldTakeFocus, heading]);

  return (
    <CardTitle
      as="h1"
      ref={headingRef}
      tabIndex={-1}
      className="text-2xl text-primary outline-none"
    >
      {heading}
    </CardTitle>
  );
}
