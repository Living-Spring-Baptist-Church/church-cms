import { createServerClient } from "@supabase/ssr";

import type { AuthCookie, AuthCookieOptions, AuthCookieStore, AuthPort } from "./auth.port";
import { createSupabaseAuthPort } from "./supabase-auth.adapter";

export type CreateSupabaseAuthOptions = {
  readonly supabaseUrl: string;
  /** The public anon key. The service role key is never accepted here (CLAUDE.md rule 8). */
  readonly anonKey: string;
  readonly cookieStore: AuthCookieStore;
  readonly totpIssuer: string;
  /** Marks the session cookies Secure. Turn off only for plain http on localhost. */
  readonly isSecureCookie: boolean;
};

const SAME_SITE_VALUES = ["lax", "strict", "none"] as const;

function toSameSite(sameSite: unknown): AuthCookieOptions["sameSite"] {
  return SAME_SITE_VALUES.find((candidate) => candidate === sameSite);
}

/**
 * Builds the auth port for one request. The session lives in httpOnly, SameSite=Lax cookies
 * (Secure unless on plain localhost), so page scripts can never read the tokens.
 * Create a new port for every request: the vendor client must not be shared between users.
 */
export function createSupabaseAuth(options: CreateSupabaseAuthOptions): AuthPort {
  const { supabaseUrl, anonKey, cookieStore, totpIssuer, isSecureCookie } = options;
  const client = createServerClient(supabaseUrl, anonKey, {
    cookieOptions: { httpOnly: true, secure: isSecureCookie, sameSite: "lax", path: "/" },
    cookies: {
      getAll: () => [...cookieStore.getAll()],
      setAll: (cookiesToSet, responseHeaders) => {
        const cookies: AuthCookie[] = cookiesToSet.map(
          ({ name, value, options: cookieOptions }) => ({
            name,
            value,
            options: {
              ...cookieOptions,
              sameSite: toSameSite(cookieOptions.sameSite),
            },
          }),
        );
        cookieStore.setAll(cookies, responseHeaders);
      },
    },
  });
  return createSupabaseAuthPort(client.auth, { totpIssuer });
}
