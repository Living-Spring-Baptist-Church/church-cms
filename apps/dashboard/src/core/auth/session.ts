import { cache } from "react";
import { notFound, redirect } from "next/navigation";
import type { Client } from "@urql/core";

import { createRequestAuth } from "@core/auth/request-context";
import { createSessionGraphqlClient } from "@core/auth/session-client";
import { hasAnyRole, hasRole, type StaffRoleName } from "@core/auth/roles";
import { determineLoginStep } from "@core/auth/login-step";
import { ROUTES } from "@core/data/routes.data";
import { logger } from "@config/logger";
import { fetchStaffProfile } from "@core/services/staff/staff.service";
import type { StaffProfile } from "@core/types/staff.types";

export type StaffSession = {
  readonly profile: StaffProfile;
  readonly email: string;
  readonly hasVerifiedFactor: boolean;
  /** Acts as the signed-in user, so pages pass it to services and RLS applies. */
  readonly client: Client;
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
  const client = createSessionGraphqlClient(state.accessToken);
  const profileResult = await fetchStaffProfile(client, state.userId);
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
  return {
    profile,
    email: state.email,
    hasVerifiedFactor: state.verifiedFactorId !== null,
    client,
  };
});

/**
 * Guards a page or layout that only some roles may use. Anyone else gets the not-found page, so a
 * module's existence is not revealed to roles that cannot use it.
 */
export async function requireRole(allowedRoles: readonly StaffRoleName[]): Promise<StaffSession> {
  const session = await requireStaff();
  if (!hasRole(session.profile.roles, allowedRoles)) {
    notFound();
  }
  return session;
}
