import type { PasswordCredentials } from "@lbc/providers";

import { determineLoginStep, type LoginStep } from "@core/auth/login-step";
import { hasAnyRole } from "@core/auth/roles";
import { LOGIN_METHOD_PASSWORD } from "@core/data/auth.data";
import type { Result } from "@core/errors/app-error";

import { createLoginSession, toAppError, type LoginServiceDependencies } from "./login-session";
import { createTwoFactorFlow } from "./two-factor.service";

export type { EnrolmentConfirmation } from "./two-factor.service";
export type { LoginGateways, LoginServiceDependencies } from "./login-session";

export function createLoginService(dependencies: LoginServiceDependencies) {
  const session = createLoginSession(dependencies);
  const { auth, loadStaffProfile, requireSignedIn, requireActiveProfile, auditLogin } = session;

  async function signIn(credentials: PasswordCredentials): Promise<Result<LoginStep>> {
    const signedIn = await auth.signInWithPassword(credentials);
    if (!signedIn.ok) {
      return { ok: false, error: toAppError(signedIn) };
    }
    const current = await requireSignedIn();
    if (!current.ok) {
      return current;
    }
    const profile = await requireActiveProfile(current.data);
    if (!profile.ok) {
      return profile;
    }
    const step = determineLoginStep({ session: current.data, profile: profile.data });
    return step === "complete" ? auditLogin(LOGIN_METHOD_PASSWORD) : { ok: true, data: step };
  }

  /** The step the login page must show for the current session, or the password form when none. */
  async function loadLoginStep(): Promise<Result<LoginStep>> {
    const state = await auth.getState();
    if (state.status === "signed_out") {
      return { ok: true, data: "password" };
    }
    const profileResult = await loadStaffProfile(state);
    if (!profileResult.ok) {
      return profileResult;
    }
    const profile = profileResult.data;
    if (profile?.isActive !== true || !hasAnyRole(profile)) {
      return { ok: true, data: "password" };
    }
    return {
      ok: true,
      data: determineLoginStep({ session: state, profile }),
    };
  }

  async function logout(): Promise<Result<undefined>> {
    const result = await auth.signOut();
    return result.ok ? { ok: true, data: undefined } : { ok: false, error: toAppError(result) };
  }

  return { signIn, loadLoginStep, logout, ...createTwoFactorFlow(session) };
}

export type LoginService = ReturnType<typeof createLoginService>;
