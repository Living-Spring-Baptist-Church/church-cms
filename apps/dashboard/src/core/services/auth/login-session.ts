import type { AuthFailureCode, AuthPort, SignedInState } from "@lbc/providers";

import { logger } from "@config/logger";
import { hasAnyRole } from "@core/auth/roles";
import type { LoginMethod } from "@core/data/auth.data";
import {
  createAppError,
  type AppError,
  type AppErrorCode,
  type Result,
} from "@core/errors/app-error";
import type { StaffProfile } from "@core/types/staff.types";

/** What the login flow needs from the database, as the signed-in user. */
export type LoginGateways = {
  readonly loadStaffProfile: (session: SignedInState) => Promise<Result<StaffProfile | null>>;
  readonly recordLogin: (session: SignedInState, method: LoginMethod) => Promise<Result<undefined>>;
};

export type LoginServiceDependencies = LoginGateways & { readonly auth: AuthPort };

const FAILURE_CODE_TO_APP_CODE: Readonly<Record<AuthFailureCode, AppErrorCode>> = {
  invalid_credentials: "invalid_credentials",
  invalid_code: "invalid_code",
  rate_limited: "rate_limited",
  not_signed_in: "session_expired",
  unavailable: "server",
};

export function toAppError(failure: { code: AuthFailureCode; detail: string }): AppError {
  return createAppError(FAILURE_CODE_TO_APP_CODE[failure.code], failure.detail);
}

// Deactivated, unknown and wrongly-typed accounts all look exactly like a wrong password.
function createRefusedLoginError(reason: string): AppError {
  return createAppError("invalid_credentials", reason);
}

/** Checks shared by every step of the login flow. */
export function createLoginSession(dependencies: LoginServiceDependencies) {
  const { auth, loadStaffProfile, recordLogin } = dependencies;

  async function endSession(): Promise<void> {
    await auth.signOut();
  }

  async function requireSignedIn(): Promise<Result<SignedInState>> {
    const state = await auth.getState();
    if (state.status === "signed_out") {
      return { ok: false, error: createAppError("session_expired", "No session") };
    }
    return { ok: true, data: state };
  }

  // Signs the visitor out and returns a refusal when the account is unknown or deactivated.
  async function requireActiveProfile(session: SignedInState): Promise<Result<StaffProfile>> {
    const profileResult = await loadStaffProfile(session);
    if (!profileResult.ok) {
      await endSession();
      return profileResult;
    }
    const profile = profileResult.data;
    if (profile?.isActive !== true) {
      await endSession();
      return { ok: false, error: createRefusedLoginError("No active staff record") };
    }
    if (!hasAnyRole(profile)) {
      logger.warn("Staff account has no role, sign in refused");
      await endSession();
      return { ok: false, error: createRefusedLoginError("Staff record has no role") };
    }
    return { ok: true, data: profile };
  }

  /** Writes the LOGIN audit row. A login that cannot be audited is not allowed (AUD-01). */
  async function auditLogin(method: LoginMethod): Promise<Result<"complete">> {
    const session = await requireSignedIn();
    if (!session.ok) {
      return session;
    }
    const audit = await recordLogin(session.data, method);
    if (audit.ok) {
      return { ok: true, data: "complete" };
    }
    await endSession();
    return audit.error.code === "forbidden"
      ? { ok: false, error: createRefusedLoginError(audit.error.technicalDetail) }
      : audit;
  }

  return { auth, loadStaffProfile, endSession, requireSignedIn, requireActiveProfile, auditLogin };
}

export type LoginSession = ReturnType<typeof createLoginSession>;
