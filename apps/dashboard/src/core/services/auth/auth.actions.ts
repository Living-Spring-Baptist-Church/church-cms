"use server";

import { redirect } from "next/navigation";

import { logger } from "@config/logger";
import type { LoginStep } from "@core/auth/login-step";
import {
  clearActivity,
  createRequestLoginService,
  readLastActivity,
  readRequestId,
  touchActivity,
} from "@core/auth/request-context";
import { withMinimumFailureDuration } from "@core/auth/min-duration";
import { isIdleExpired } from "@core/auth/session-activity";
import { SIGN_IN_MIN_FAILURE_MS } from "@core/data/auth.data";
import { ROUTES } from "@core/data/routes.data";
import {
  createAppError,
  toErrorView,
  type ActionResult,
  type AppError,
  type Result,
} from "@core/errors/app-error";
import {
  enrolmentCodeSchema,
  loginSchema,
  totpCodeSchema,
  type EnrolmentCodeInput,
  type LoginInput,
  type TotpCodeInput,
} from "@core/schemas/auth.schema";
import type { EnrolmentView } from "@core/types/auth.types";

type ActionFailure = Extract<ActionResult, { ok: false }>;

async function failWith(operation: string, error: AppError): Promise<ActionFailure> {
  // Technical detail goes to the log only. It never names the email or the password.
  logger.warn(`${operation} failed`, {
    code: error.code,
    detail: error.technicalDetail,
    requestId: await readRequestId(),
  });
  return { ok: false, error: toErrorView(error) };
}

function invalidInput(operation: string): Promise<ActionFailure> {
  return failWith(operation, createAppError("validation", "Input failed schema validation"));
}

// Server actions are separate POST requests the proxy may not cover, so each one checks idle time itself.
async function endSessionWhenIdle(): Promise<ActionFailure | null> {
  if (!isIdleExpired({ lastActivityMs: await readLastActivity(), nowMs: Date.now() })) {
    return null;
  }
  await (await createRequestLoginService("writable")).logout();
  await clearActivity();
  return failWith("Session check", createAppError("session_expired", "Idle timeout"));
}

async function continueAfterStep(
  operation: string,
  result: Result<LoginStep>,
): Promise<ActionFailure> {
  if (!result.ok) {
    return failWith(operation, result.error);
  }
  await touchActivity(Date.now());
  return redirect(result.data === "complete" ? ROUTES.home : ROUTES.login);
}

/** Password step. On success it redirects to the next step, so a return value is always a failure. */
export async function signInAction(input: LoginInput): Promise<ActionFailure> {
  const parsed = loginSchema.safeParse(input);
  if (!parsed.success) {
    return invalidInput("Sign in");
  }
  const loginService = await createRequestLoginService("writable");
  const result = await withMinimumFailureDuration(() => loginService.signIn(parsed.data), {
    minimumMs: SIGN_IN_MIN_FAILURE_MS,
  });
  return continueAfterStep("Sign in", result);
}

/** Code step for a user who already owns an authenticator app. */
export async function verifyLoginCodeAction(input: TotpCodeInput): Promise<ActionFailure> {
  const parsed = totpCodeSchema.safeParse(input);
  if (!parsed.success) {
    return invalidInput("Verify code");
  }
  const idleFailure = await endSessionWhenIdle();
  if (idleFailure) {
    return idleFailure;
  }
  const loginService = await createRequestLoginService("writable");
  return continueAfterStep("Verify code", await loginService.verifyLoginCode(parsed.data.code));
}

export async function startEnrolmentAction(): Promise<ActionResult<EnrolmentView>> {
  const idleFailure = await endSessionWhenIdle();
  if (idleFailure) {
    return idleFailure;
  }
  const loginService = await createRequestLoginService("writable");
  const result = await loginService.startEnrolment();
  if (!result.ok) {
    return failWith("Start enrolment", result.error);
  }
  return { ok: true, data: result.data };
}

export async function confirmEnrolmentAction(input: EnrolmentCodeInput): Promise<ActionFailure> {
  const parsed = enrolmentCodeSchema.safeParse(input);
  if (!parsed.success) {
    return invalidInput("Confirm enrolment");
  }
  const idleFailure = await endSessionWhenIdle();
  if (idleFailure) {
    return idleFailure;
  }
  const loginService = await createRequestLoginService("writable");
  return continueAfterStep("Confirm enrolment", await loginService.confirmEnrolment(parsed.data));
}

/** Ends the session and sends the visitor to the login page. Also used by the sign out button. */
export async function logoutAction(): Promise<void> {
  const loginService = await createRequestLoginService("writable");
  const result = await loginService.logout();
  if (!result.ok) {
    await failWith("Sign out", result.error);
  }
  await clearActivity();
  redirect(ROUTES.login);
}
