export const ROUTES = {
  home: "/",
  login: "/login",
  accountSecurity: "/account/security",
  /** Route handler that ends the session and returns to the login page. */
  sessionEnd: "/session/end",
  members: "/members",
  membersNew: "/members/new",
  attendance: "/attendance",
  programs: "/programs",
  finance: "/finance",
  messaging: "/messaging",
  reports: "/reports",
  content: "/content",
  audit: "/audit",
  settings: "/settings",
} as const;

/** Reachable without a signed-in session. The login page decides what to show itself. */
export const PUBLIC_ROUTES: readonly string[] = [ROUTES.login, ROUTES.sessionEnd];
