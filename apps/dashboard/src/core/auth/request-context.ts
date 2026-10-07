import { createSupabaseAuth, type AuthPort } from "@lbc/providers";
import { cookies, headers } from "next/headers";

import { readPublicEnv } from "@config/env";
import { createSessionGraphqlClient } from "@core/auth/session-client";
import {
  createActivityCookie,
  createExpiredActivityCookie,
  isSecureRequest,
  readSecureCookieHints,
} from "@core/auth/cookies";
import { parseActivityTimestamp } from "@core/auth/session-activity";
import { ACTIVITY_COOKIE_NAME, REQUEST_ID_HEADER } from "@core/data/auth.data";
import { AUTH_COPY } from "@core/copy/auth.copy";
import { createLoginService, type LoginService } from "@core/services/auth/login.service";
import { recordLogin } from "@core/services/audit/audit.service";
import { fetchStaffProfile } from "@core/services/staff/staff.service";

/** Server components may read the session but cannot write cookies; the proxy refreshes it instead. */
export type CookieAccess = "read_only" | "writable";

export async function createRequestAuth(access: CookieAccess): Promise<AuthPort> {
  const { supabaseUrl, supabaseAnonKey } = readPublicEnv(process.env);
  const cookieJar = await cookies();
  const requestHeaders = await headers();
  return createSupabaseAuth({
    supabaseUrl,
    anonKey: supabaseAnonKey,
    totpIssuer: AUTH_COPY.logoAlt,
    isSecureCookie: isSecureRequest(readSecureCookieHints(requestHeaders)),
    cookieStore: {
      getAll: () => cookieJar.getAll(),
      setAll: (cookiesToSet) => {
        if (access === "read_only") {
          return;
        }
        cookiesToSet.forEach(({ name, value, options }) => {
          cookieJar.set(name, value, options);
        });
      },
    },
  });
}

export async function createRequestLoginService(access: CookieAccess): Promise<LoginService> {
  const auth = await createRequestAuth(access);
  return createLoginService({
    auth,
    loadStaffProfile: (session) =>
      fetchStaffProfile(createSessionGraphqlClient(session.accessToken), session.userId),
    recordLogin: (session, method) =>
      recordLogin({
        client: createSessionGraphqlClient(session.accessToken),
        staffId: session.userId,
        method,
      }),
  });
}

export async function isRequestSecure(): Promise<boolean> {
  return isSecureRequest(readSecureCookieHints(await headers()));
}

export async function readLastActivity(): Promise<number | null> {
  const cookieJar = await cookies();
  return parseActivityTimestamp(cookieJar.get(ACTIVITY_COOKIE_NAME)?.value);
}

export async function touchActivity(nowMs: number): Promise<void> {
  const { name, value, options } = createActivityCookie(nowMs, await isRequestSecure());
  (await cookies()).set(name, value, options);
}

export async function clearActivity(): Promise<void> {
  const { name, value, options } = createExpiredActivityCookie(await isRequestSecure());
  (await cookies()).set(name, value, options);
}

export async function readRequestId(): Promise<string | undefined> {
  return (await headers()).get(REQUEST_ID_HEADER) ?? undefined;
}
