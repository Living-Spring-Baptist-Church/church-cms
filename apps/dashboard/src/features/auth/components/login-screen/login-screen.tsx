import logoFull from "@lbc/ui/assets/brand/lbc-logo-full.png";
import Image from "next/image";

import { Alert, Card, CardContent, CardDescription, CardHeader } from "@lbc/ui";

import type { LoginStep } from "@core/auth/login-step";
import { AUTH_COPY } from "@core/copy/auth.copy";
import {
  confirmEnrolmentAction,
  logoutAction,
  signInAction,
  startEnrolmentAction,
  verifyLoginCodeAction,
} from "@core/services/auth/auth.actions";
import { StepHeading } from "@features/auth/components/step-heading/step-heading";
import { LoginForm } from "@features/auth/components/login-form/login-form";
import { LogoutButton } from "@features/auth/components/logout-button/logout-button";
import { TotpCodeForm } from "@features/auth/components/totp-code-form/totp-code-form";
import { TotpEnrolForm } from "@features/auth/components/totp-enrol-form/totp-enrol-form";

type LoginScreenProps = {
  step: Exclude<LoginStep, "complete">;
  /** True when the visitor was signed out for being idle. */
  wasIdleSignedOut: boolean;
};

function renderStep(step: LoginScreenProps["step"]) {
  switch (step) {
    case "password":
      return {
        heading: AUTH_COPY.login.heading,
        description: AUTH_COPY.login.description,
        body: <LoginForm signIn={signInAction} />,
      };
    case "verify_code":
      return {
        heading: AUTH_COPY.verify.heading,
        description: AUTH_COPY.verify.description,
        body: (
          <TotpCodeForm
            label={AUTH_COPY.verify.codeLabel}
            submitLabel={AUTH_COPY.verify.submit}
            pendingLabel={AUTH_COPY.verify.submitting}
            submitCode={verifyLoginCodeAction}
          />
        ),
      };
    case "enrol":
      return {
        heading: AUTH_COPY.enrol.heading,
        description: AUTH_COPY.enrol.requiredDescription,
        body: (
          <TotpEnrolForm
            startEnrolment={startEnrolmentAction}
            confirmEnrolment={confirmEnrolmentAction}
          />
        ),
      };
  }
}

/** The login page content: logo, the card for the current step, and a way out of a half finished login. */
export function LoginScreen({ step, wasIdleSignedOut }: LoginScreenProps) {
  const { heading, description, body } = renderStep(step);
  return (
    <main
      id="main-content"
      className="mx-auto flex min-h-screen w-full max-w-md flex-col justify-center gap-6 px-4 py-8"
    >
      <Image src={logoFull} alt={AUTH_COPY.logoAlt} priority className="h-auto w-48 self-center" />
      <Card>
        <CardHeader>
          <StepHeading heading={heading} shouldTakeFocus={step !== "password"} />
          <CardDescription>{description}</CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-4">
          {wasIdleSignedOut && step === "password" ? (
            <Alert variant="info" role="status">
              {AUTH_COPY.idleNotice}
            </Alert>
          ) : null}
          {body}
          {step === "password" ? null : <LogoutButton signOut={logoutAction} variant="ghost" />}
        </CardContent>
      </Card>
    </main>
  );
}
