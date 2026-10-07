import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { createRequestLoginService } from "@core/auth/request-context";
import { AUTH_COPY } from "@core/copy/auth.copy";
import { LOGIN_REASON_IDLE, LOGIN_REASON_PARAM } from "@core/data/auth.data";
import { ROUTES } from "@core/data/routes.data";
import { LoginScreen } from "@features/auth/components/login-screen/login-screen";

export const metadata: Metadata = { title: AUTH_COPY.login.pageTitle };

type LoginPageProps = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function LoginPage({ searchParams }: LoginPageProps) {
  const reason = (await searchParams)[LOGIN_REASON_PARAM];
  const loginService = await createRequestLoginService("read_only");
  const stepResult = await loginService.loadLoginStep();
  if (!stepResult.ok) {
    throw new Error(stepResult.error.message);
  }
  if (stepResult.data === "complete") {
    redirect(ROUTES.home);
  }
  return <LoginScreen step={stepResult.data} wasIdleSignedOut={reason === LOGIN_REASON_IDLE} />;
}
