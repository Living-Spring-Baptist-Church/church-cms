import { cache } from "react";
import { redirect } from "next/navigation";

import { createRequestAuth } from "@core/auth/request-context";
import { createSessionGraphqlClient } from "@core/auth/session-client";
import { hasAnyRole } from "@core/auth/roles";
import { determineLoginStep } from "@core/auth/login-step";
import { ROUTES } from "@core/data/routes.data";
import { logger } from "@config/logger";
import { fetchStaffProfile } from "@core/services/staff/staff.service";
import type { StaffProfile } from "@core/types/staff.types";

export type StaffSession = {
  readonly profile: StaffProfile;
  readonly email: string;
  readonly hasVerifiedFactor: boolean;
};

/**
 * Guards a layout or page: returns the signed-in, active staff member who finished login, and
 * redirects everybody else. The database enforces permissions again with RLS on every query.
 * Cached per request, so the layout and the page share one lookup.
 */
export const requireStaff = cache(async (): Promise<StaffSession> => {
  const auth = await createRequestAuth("read_only");
  const state = await auth.getState();
  if (state.status === "signed_out") {
    return redirect(ROUTES.login);
  }
  const profileResult = await fetchStaffProfile(
    createSessionGraphqlClient(state.accessToken),
    state.userId,
  );
  if (!profileResult.ok) {
    logger.error("Could not load the staff profile", {
      code: profileResult.error.code,
      detail: profileResult.error.technicalDetail,
    });
    throw new Error(profileResult.error.message);
  }
  const { data: profile } = profileResult;
  // A deactivated or role-less account keeps its cookies until the session is ended through the route handler.
  if (profile?.isActive !== true || !hasAnyRole(profile)) {
    return redirect(ROUTES.sessionEnd);
  }
  if (determineLoginStep({ session: state, profile }) !== "complete") {
    return redirect(ROUTES.login);
  }
  return { profile, email: state.email, hasVerifiedFactor: state.verifiedFactorId !== null };
});
