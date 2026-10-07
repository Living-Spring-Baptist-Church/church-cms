"use client";

import Image from "next/image";
import { useState, useTransition } from "react";

import { Alert, Button, FormField, Icon } from "@lbc/ui";

import { AUTH_COPY } from "@core/copy/auth.copy";
import type { ActionResult, AppErrorView } from "@core/errors/app-error";
import type { EnrolmentCodeInput, TotpCodeInput } from "@core/schemas/auth.schema";
import type { EnrolmentView } from "@core/types/auth.types";
import { TotpCodeForm } from "@features/auth/components/totp-code-form/totp-code-form";

const QR_CODE_SIZE_PIXELS = 192;

type TotpEnrolFormProps = {
  startEnrolment: () => Promise<ActionResult<EnrolmentView>>;
  /** Resolves only on failure: success redirects to the dashboard. */
  confirmEnrolment: (input: EnrolmentCodeInput) => Promise<{ ok: false; error: AppErrorView }>;
};

export function TotpEnrolForm({ startEnrolment, confirmEnrolment }: TotpEnrolFormProps) {
  const [enrolment, setEnrolment] = useState<EnrolmentView | null>(null);
  const [startError, setStartError] = useState<string | null>(null);
  const [hasCopiedSecret, setHasCopiedSecret] = useState(false);
  const [isStarting, startTransition] = useTransition();

  const start = () => {
    setStartError(null);
    startTransition(async () => {
      const result = await startEnrolment();
      if (result.ok) {
        setEnrolment(result.data);
      } else {
        setStartError(result.error.message);
      }
    });
  };

  if (enrolment === null) {
    return (
      <div className="flex flex-col gap-4">
        <div aria-live="assertive">
          {startError ? <Alert variant="destructive">{startError}</Alert> : null}
        </div>
        <Button onClick={start} disabled={isStarting} aria-busy={isStarting}>
          <Icon name="shield-check" />
          {isStarting ? AUTH_COPY.enrol.starting : AUTH_COPY.enrol.start}
        </Button>
      </div>
    );
  }

  const copySecret = () => {
    void navigator.clipboard.writeText(enrolment.secret).then(() => {
      setHasCopiedSecret(true);
    });
  };
  const submitCode = (input: TotpCodeInput) =>
    confirmEnrolment({ factorId: enrolment.factorId, code: input.code });

  return (
    <div className="flex flex-col gap-6">
      <section aria-labelledby="enrol-steps-heading" className="flex flex-col gap-4">
        <h2 id="enrol-steps-heading" className="text-lg font-semibold">
          {AUTH_COPY.enrol.stepsHeading}
        </h2>
        <p className="text-sm text-muted-foreground">{AUTH_COPY.enrol.scanInstruction}</p>
        <Image
          src={enrolment.qrCodeDataUri}
          alt={AUTH_COPY.enrol.qrAlt}
          width={QR_CODE_SIZE_PIXELS}
          height={QR_CODE_SIZE_PIXELS}
          unoptimized
          className="size-48 self-center rounded-md border border-border bg-background p-2"
        />
        <FormField
          label={AUTH_COPY.enrol.secretLabel}
          hint={AUTH_COPY.enrol.secretHelp}
          value={enrolment.secret}
          readOnly
          spellCheck={false}
          autoComplete="off"
        />
        <Button variant="outline" onClick={copySecret}>
          <Icon name="copy" />
          {hasCopiedSecret ? AUTH_COPY.enrol.copiedSecret : AUTH_COPY.enrol.copySecret}
        </Button>
        <p role="status" className="sr-only">
          {hasCopiedSecret ? AUTH_COPY.enrol.copiedSecret : ""}
        </p>
      </section>
      <TotpCodeForm
        label={AUTH_COPY.enrol.codeLabel}
        hint={AUTH_COPY.enrol.codeHelp}
        submitLabel={AUTH_COPY.enrol.submit}
        pendingLabel={AUTH_COPY.enrol.submitting}
        submitCode={submitCode}
      />
    </div>
  );
}
