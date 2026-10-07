export const ROUTES = {
  home: "/",
  login: "/login",
  accountSecurity: "/account/security",
  /** Route handler that ends the session and returns to the login page. */
  sessionEnd: "/session/end",
} as const;

/** Reachable without a signed-in session. The login page decides what to show itself. */
export const PUBLIC_ROUTES: readonly string[] = [ROUTES.login, ROUTES.sessionEnd];
