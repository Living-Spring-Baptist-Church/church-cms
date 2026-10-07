import type { AssuranceLevel } from "@lbc/providers";

import { PUBLIC_ROUTES } from "@core/data/routes.data";

export type AccessRequest = {
  readonly pathname: string;
  readonly isSignedIn: boolean;
  readonly isIdleExpired: boolean;
  readonly currentLevel: AssuranceLevel;
  /** aal2 when the user owns a verified authenticator app. */
  readonly nextLevel: AssuranceLevel;
};

export type AccessDecision =
  /** Let the request through and count it as activity. */
  | { readonly kind: "allow" }
  /** Send the visitor to the login page; the session stays as it is. */
  | { readonly kind: "redirect_to_login" }
  /** The session idled out: end it, then send the visitor to the login page. */
  | { readonly kind: "expire" };

export function isPublicRoute(pathname: string): boolean {
  return PUBLIC_ROUTES.some((route) => pathname === route);
}

function ownsPendingCode({ currentLevel, nextLevel }: AccessRequest): boolean {
  return currentLevel === "aal1" && nextLevel === "aal2";
}

/**
 * The route table of the proxy. Cheap and pure: it needs no database, so it runs on every request.
 * Whether a role must have two-factor needs the database, so layouts and pages check that through
 * requireStaff(). Anyone who already owns an authenticator app is held at aal1 here.
 */
export function decideAccess(request: AccessRequest): AccessDecision {
  if (request.isSignedIn && request.isIdleExpired) {
    return { kind: "expire" };
  }
  if (isPublicRoute(request.pathname)) {
    return { kind: "allow" };
  }
  if (!request.isSignedIn || ownsPendingCode(request)) {
    return { kind: "redirect_to_login" };
  }
  return { kind: "allow" };
}
