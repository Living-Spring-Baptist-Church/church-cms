import { Slot } from "@radix-ui/react-slot";
import { cva, type VariantProps } from "class-variance-authority";
import type { ComponentProps, MouseEvent } from "react";

import { cn } from "#helpers/cn.utils";

export const buttonVariants = cva(
  "inline-flex shrink-0 cursor-pointer items-center justify-center gap-2 rounded-md text-sm font-medium whitespace-nowrap focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background focus-visible:outline-none disabled:pointer-events-none disabled:opacity-50",
  {
    variants: {
      variant: {
        default: "bg-primary text-primary-foreground hover:bg-primary/90",
        secondary: "bg-secondary text-secondary-foreground hover:bg-secondary/80",
        outline:
          "border border-input bg-background text-foreground hover:bg-accent hover:text-accent-foreground",
        ghost: "text-foreground hover:bg-accent hover:text-accent-foreground",
        destructive: "bg-destructive text-destructive-foreground hover:bg-destructive/90",
        link: "text-link underline-offset-4 hover:underline",
      },
      size: {
        default: "h-11 px-4",
        lg: "h-12 px-6 text-base",
        icon: "size-11",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  },
);

const DISABLED_CHILD_CLASS_NAME = "pointer-events-none opacity-50";

// Screen readers and Enter still send clicks, which pointer-events does not stop. Stopping the
// event in the capture phase also skips any onClick on the child itself, like a native disabled button.
function blockActivation(event: MouseEvent<HTMLElement>) {
  event.preventDefault();
  event.stopPropagation();
}

export type ButtonProps = ComponentProps<"button"> &
  VariantProps<typeof buttonVariants> & {
    /** Render the single child element (for example a next/link) with button styles. */
    asChild?: boolean;
  };

export function Button({
  className,
  variant,
  size,
  asChild = false,
  type = "button",
  ...buttonProps
}: ButtonProps) {
  const buttonClassName = cn(buttonVariants({ variant, size }), className);

  if (asChild) {
    const { disabled: isDisabled = false, ...childProps } = buttonProps;
    // A link cannot be disabled natively, so remove it from the tab order and block clicks.
    const disabledChildProps = isDisabled
      ? {
          "aria-disabled": true,
          tabIndex: -1,
          className: cn(buttonClassName, DISABLED_CHILD_CLASS_NAME),
          onClickCapture: blockActivation,
          onClick: blockActivation,
        }
      : { className: buttonClassName };
    return <Slot data-slot="button" {...childProps} {...disabledChildProps} />;
  }

  return <button data-slot="button" type={type} className={buttonClassName} {...buttonProps} />;
}
