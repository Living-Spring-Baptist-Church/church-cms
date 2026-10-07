import type { SignedInState } from "@lbc/providers";

import { profileRequiresMfa, type RoleHolder } from "@core/auth/roles";

export type LoginStep = "password" | "verify_code" | "enrol" | "complete";

type StepInput = {
  readonly session: Pick<SignedInState, "currentLevel" | "verifiedFactorId">;
  readonly profile: RoleHolder;
};

/**
 * Where a signed-in visitor stands on the way to the dashboard.
 * Anyone with an authenticator app must prove a code; the roles that require two-factor and have no
 * app yet must enrol one; everybody else is done after the password.
 */
export function determineLoginStep({ session, profile }: StepInput): LoginStep {
  if (session.currentLevel === "aal2") {
    return "complete";
  }
  if (session.verifiedFactorId !== null) {
    return "verify_code";
  }
  return profileRequiresMfa(profile) ? "enrol" : "complete";
}
