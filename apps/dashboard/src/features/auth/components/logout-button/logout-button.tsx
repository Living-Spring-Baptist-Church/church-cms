"use client";

import { useFormStatus } from "react-dom";

import { Button, Icon, type ButtonProps } from "@lbc/ui";

import { AUTH_COPY } from "@core/copy/auth.copy";

type LogoutButtonProps = {
  signOut: () => Promise<void>;
  variant?: ButtonProps["variant"];
  className?: string;
};

function SubmitButton({ variant, className }: Pick<LogoutButtonProps, "variant" | "className">) {
  const { pending } = useFormStatus();
  return (
    <Button
      type="submit"
      variant={variant}
      disabled={pending}
      aria-busy={pending}
      {...(className === undefined ? {} : { className })}
    >
      <Icon name="log-out" />
      {pending ? AUTH_COPY.logout.pending : AUTH_COPY.logout.label}
    </Button>
  );
}

/** Signs out through a server action, so it works even before the page scripts have loaded. */
export function LogoutButton({ signOut, variant = "outline", className }: LogoutButtonProps) {
  return (
    <form action={signOut}>
      <SubmitButton variant={variant} {...(className === undefined ? {} : { className })} />
    </form>
  );
}
