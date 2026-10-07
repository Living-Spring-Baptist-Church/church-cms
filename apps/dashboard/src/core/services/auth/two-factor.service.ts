import type { SignedInState, TotpEnrolment } from "@lbc/providers";

import type { LoginStep } from "@core/auth/login-step";
import { profileRequiresMfa } from "@core/auth/roles";
import { LOGIN_METHOD_PASSWORD_AND_TOTP } from "@core/data/auth.data";
import { createAppError, type AppError, type Result } from "@core/errors/app-error";

import { toAppError, type LoginSession } from "./login-session";

export type EnrolmentConfirmation = {
  readonly factorId: string;
  readonly code: string;
};

function refuse(reason: string): { ok: false; error: AppError } {
  return { ok: false, error: createAppError("forbidden", reason) };
}

/**
 * A second authenticator app may only be added from a session that already proved the first one.
 * Without this, a password alone could enrol the attacker's own app and reach aal2.
 */
function mayEnrol(session: SignedInState): boolean {
  return session.verifiedFactorId === null || session.currentLevel === "aal2";
}

/** The two-factor steps: proving a code at sign in, and enrolling an authenticator app. */
export function createTwoFactorFlow(session: LoginSession) {
  const { auth, requireSignedIn, requireActiveProfile, auditLogin } = session;

  async function verifyLoginCode(code: string): Promise<Result<LoginStep>> {
    const signedIn = await requireSignedIn();
    if (!signedIn.ok) {
      return signedIn;
    }
    if (signedIn.data.verifiedFactorId === null) {
      return { ok: false, error: createAppError("session_expired", "No authenticator app") };
    }
    // Already at aal2 means this login was audited; a second call must not write a second row.
    if (signedIn.data.currentLevel === "aal2") {
      return refuse("The login is already complete");
    }
    const verified = await auth.verifyTotp({ factorId: signedIn.data.verifiedFactorId, code });
    if (!verified.ok) {
      return { ok: false, error: toAppError(verified) };
    }
    return auditLogin(LOGIN_METHOD_PASSWORD_AND_TOTP);
  }

  async function startEnrolment(): Promise<Result<TotpEnrolment>> {
    const signedIn = await requireSignedIn();
    if (!signedIn.ok) {
      return signedIn;
    }
    if (!mayEnrol(signedIn.data)) {
      return refuse("Enrolment needs a session that passed two-factor");
    }
    const profile = await requireActiveProfile(signedIn.data);
    if (!profile.ok) {
      return profile;
    }
    const enrolment = await auth.startTotpEnrolment();
    return enrolment.ok
      ? { ok: true, data: enrolment.data }
      : { ok: false, error: toAppError(enrolment) };
  }

  // Only an app this user started and never confirmed can be confirmed here, never a verified one.
  async function requirePendingFactor(factorId: string): Promise<Result<undefined>> {
    const pending = await auth.listUnverifiedTotpFactorIds();
    if (!pending.ok) {
      return { ok: false, error: toAppError(pending) };
    }
    return pending.data.includes(factorId)
      ? { ok: true, data: undefined }
      : refuse("The factor is not a pending enrolment of this user");
  }

  async function confirmEnrolment(confirmation: EnrolmentConfirmation): Promise<Result<LoginStep>> {
    const signedIn = await requireSignedIn();
    if (!signedIn.ok) {
      return signedIn;
    }
    if (!mayEnrol(signedIn.data)) {
      return refuse("Enrolment needs a session that passed two-factor");
    }
    const profile = await requireActiveProfile(signedIn.data);
    if (!profile.ok) {
      return profile;
    }
    const pending = await requirePendingFactor(confirmation.factorId);
    if (!pending.ok) {
      return pending;
    }
    const verified = await auth.verifyTotp(confirmation);
    if (!verified.ok) {
      return { ok: false, error: toAppError(verified) };
    }
    // Forced enrolment is the second half of a login that is still at aal1, so it is audited once here.
    // Enrolling from settings, or while already at aal2, belongs to a login that was audited earlier.
    const isFinishingLogin =
      signedIn.data.currentLevel === "aal1" && profileRequiresMfa(profile.data);
    return isFinishingLogin
      ? auditLogin(LOGIN_METHOD_PASSWORD_AND_TOTP)
      : { ok: true, data: "complete" };
  }

  return { verifyLoginCode, startEnrolment, confirmEnrolment };
}
