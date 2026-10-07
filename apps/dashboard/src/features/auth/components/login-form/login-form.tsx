"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { useState, useTransition } from "react";
import { useForm } from "react-hook-form";

import { Alert, Button, FormField } from "@lbc/ui";

import { AUTH_COPY } from "@core/copy/auth.copy";
import { loginSchema, type LoginInput } from "@core/schemas/auth.schema";
import type { AppErrorView } from "@core/errors/app-error";

type LoginFormProps = {
  /** Resolves only on failure: success redirects to the next step. */
  signIn: (input: LoginInput) => Promise<{ ok: false; error: AppErrorView }>;
};

export function LoginForm({ signIn }: LoginFormProps) {
  const [serverError, setServerError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();
  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<LoginInput>({ resolver: zodResolver(loginSchema), mode: "onSubmit" });

  const submit = handleSubmit((values) => {
    setServerError(null);
    startTransition(async () => {
      const failure = await signIn(values);
      setServerError(failure.error.message);
    });
  });

  return (
    <form
      onSubmit={(event) => {
        void submit(event);
      }}
      noValidate
      className="flex flex-col gap-4"
    >
      <FormField
        label={AUTH_COPY.login.emailLabel}
        type="email"
        autoComplete="username"
        inputMode="email"
        autoCapitalize="none"
        spellCheck={false}
        error={errors.email?.message}
        {...register("email")}
      />
      <FormField
        label={AUTH_COPY.login.passwordLabel}
        type="password"
        autoComplete="current-password"
        error={errors.password?.message}
        {...register("password")}
      />
      <div aria-live="assertive">
        {serverError ? <Alert variant="destructive">{serverError}</Alert> : null}
      </div>
      <Button type="submit" disabled={isPending} aria-busy={isPending}>
        {isPending ? AUTH_COPY.login.submitting : AUTH_COPY.login.submit}
      </Button>
    </form>
  );
}
