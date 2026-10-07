"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { useState, useTransition } from "react";
import { useForm } from "react-hook-form";
import { z } from "zod";

import { Alert, Button, FormField } from "@lbc/ui";

import { TOTP_CODE_LENGTH } from "@core/data/auth.data";
import type { AppErrorView } from "@core/errors/app-error";
import { totpCodeSchema, type TotpCodeInput } from "@core/schemas/auth.schema";

const NON_DIGIT_PATTERN = /\D/g;

type TotpCodeFormProps = {
  label: string;
  hint?: string;
  submitLabel: string;
  pendingLabel: string;
  /** Resolves only on failure: success redirects to the next screen. */
  submitCode: (input: TotpCodeInput) => Promise<{ ok: false; error: AppErrorView }>;
};

/** The six digit code entry shared by the sign in step and the enrolment step. */
export function TotpCodeForm({
  label,
  hint,
  submitLabel,
  pendingLabel,
  submitCode,
}: TotpCodeFormProps) {
  const [serverError, setServerError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();
  const {
    register,
    handleSubmit,
    setValue,
    formState: { errors },
  } = useForm<z.input<typeof totpCodeSchema>>({
    resolver: zodResolver(totpCodeSchema),
    defaultValues: { code: "" },
  });

  const submit = handleSubmit((values) => {
    setServerError(null);
    startTransition(async () => {
      const failure = await submitCode(values);
      setServerError(failure.error.message);
      setValue("code", "");
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
        label={label}
        {...(hint === undefined ? {} : { hint })}
        inputMode="numeric"
        autoComplete="one-time-code"
        pattern="[0-9]*"
        error={errors.code?.message}
        {...register("code", {
          onChange: (event: { target: { value: string } }) => {
            const digits = event.target.value
              .replace(NON_DIGIT_PATTERN, "")
              .slice(0, TOTP_CODE_LENGTH);
            event.target.value = digits;
            setValue("code", digits);
          },
        })}
      />
      <div aria-live="assertive">
        {serverError ? <Alert variant="destructive">{serverError}</Alert> : null}
      </div>
      <Button type="submit" disabled={isPending} aria-busy={isPending}>
        {isPending ? pendingLabel : submitLabel}
      </Button>
    </form>
  );
}
