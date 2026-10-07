// Next.js 16 renamed middleware.ts to proxy.ts (docs/standards/frontend.md still says middleware.ts).
import { createSupabaseAuth, type AuthCookie } from "@lbc/providers";
import { NextResponse, type NextRequest } from "next/server";

import { readPublicEnv } from "@config/env";
import { decideAccess, type AccessDecision } from "@core/auth/access-policy";
import {
  createActivityCookie,
  createExpiredActivityCookie,
  isSecureRequest,
  readSecureCookieHints,
} from "@core/auth/cookies";
import { isIdleExpired, parseActivityTimestamp } from "@core/auth/session-activity";
import { AUTH_COPY } from "@core/copy/auth.copy";
import {
  ACTIVITY_COOKIE_NAME,
  CACHE_CONTROL_HEADER,
  LOGIN_REASON_IDLE,
  LOGIN_REASON_PARAM,
  PRIVATE_CACHE_CONTROL,
  REQUEST_ID_HEADER,
} from "@core/data/auth.data";
import { ROUTES } from "@core/data/routes.data";

type PendingResponseState = {
  readonly cookies: AuthCookie[];
  readonly headers: Record<string, string>;
};

type ResponsePlan = {
  readonly decision: AccessDecision;
  readonly isSignedIn: boolean;
  readonly isSecure: boolean;
  readonly nowMs: number;
};

function buildLoginRedirect(request: NextRequest, decision: AccessDecision): NextResponse {
  const loginUrl = request.nextUrl.clone();
  loginUrl.pathname = ROUTES.login;
  loginUrl.search = decision.kind === "expire" ? `?${LOGIN_REASON_PARAM}=${LOGIN_REASON_IDLE}` : "";
  return NextResponse.redirect(loginUrl);
}

function buildAllowedResponse(request: NextRequest, pending: PendingResponseState): NextResponse {
  // Pass refreshed session cookies on to the server components of this same request.
  pending.cookies.forEach(({ name, value }) => {
    request.cookies.set(name, value);
  });
  const requestHeaders = new Headers(request.headers);
  requestHeaders.set(REQUEST_ID_HEADER, crypto.randomUUID());
  return NextResponse.next({ request: { headers: requestHeaders } });
}

function applyCookies(
  response: NextResponse,
  pending: PendingResponseState,
  plan: ResponsePlan,
): void {
  pending.cookies.forEach(({ name, value, options }) => {
    response.cookies.set(name, value, options);
  });
  Object.entries(pending.headers).forEach(([headerName, headerValue]) => {
    response.headers.set(headerName, headerValue);
  });
  if (plan.decision.kind === "expire") {
    const expired = createExpiredActivityCookie(plan.isSecure);
    response.cookies.set(expired.name, expired.value, expired.options);
  } else if (plan.decision.kind === "allow" && plan.isSignedIn) {
    const activity = createActivityCookie(plan.nowMs, plan.isSecure);
    response.cookies.set(activity.name, activity.value, activity.options);
  }
  response.headers.set(CACHE_CONTROL_HEADER, PRIVATE_CACHE_CONTROL);
}

/**
 * Runs before every dashboard request. It validates the session with the auth provider (refreshing
 * the tokens when needed), enforces the 30 minute idle limit (SET-04) and sends visitors without a
 * finished login to /login. Deeper checks (active account, roles that need two-factor) happen in
 * requireStaff(), because they need the database.
 */
export async function proxy(request: NextRequest): Promise<NextResponse> {
  const nowMs = Date.now();
  const { supabaseUrl, supabaseAnonKey } = readPublicEnv(process.env);
  const isSecure = isSecureRequest(
    readSecureCookieHints(request.headers, request.nextUrl.protocol),
  );
  const pending: PendingResponseState = { cookies: [], headers: {} };
  const auth = createSupabaseAuth({
    supabaseUrl,
    anonKey: supabaseAnonKey,
    totpIssuer: AUTH_COPY.logoAlt,
    isSecureCookie: isSecure,
    cookieStore: {
      getAll: () => request.cookies.getAll(),
      setAll: (cookiesToSet, responseHeaders) => {
        pending.cookies.push(...cookiesToSet);
        Object.assign(pending.headers, responseHeaders);
      },
    },
  });

  const state = await auth.getState();
  const isSignedIn = state.status === "signed_in";
  const lastActivityMs = parseActivityTimestamp(request.cookies.get(ACTIVITY_COOKIE_NAME)?.value);
  const decision = decideAccess({
    pathname: request.nextUrl.pathname,
    isSignedIn,
    isIdleExpired: isIdleExpired({ lastActivityMs, nowMs }),
    currentLevel: state.status === "signed_in" ? state.currentLevel : "aal1",
    nextLevel: state.status === "signed_in" ? state.nextLevel : "aal1",
  });
  if (decision.kind === "expire") {
    await auth.signOut();
  }

  const response =
    decision.kind === "allow"
      ? buildAllowedResponse(request, pending)
      : buildLoginRedirect(request, decision);
  applyCookies(response, pending, { decision, isSignedIn, isSecure, nowMs });
  return response;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|icon.png|apple-icon.png).*)"],
};
