import type { AuthCookieOptions } from "@lbc/providers";

import { ACTIVITY_COOKIE_NAME, FORWARDED_PROTO_HEADER, ORIGIN_HEADER } from "@core/data/auth.data";

const HTTPS_PROTOCOL = "https:";
const HTTPS_SCHEME = "https";
const COOKIE_PATH = "/";
const EXPIRED_MAX_AGE_SECONDS = 0;

type HeaderReader = { get(name: string): string | null };

export type SecureCookieHints = {
  readonly forwardedProto: string | null;
  /** Protocol of the request URL, such as "http:", when the runtime knows it. */
  readonly urlProtocol?: string | undefined;
  /** Origin header of a server action request, such as "http://127.0.0.1:3000". */
  readonly origin: string | null;
};

function protocolOfOrigin(origin: string | null): string | undefined {
  return origin === null ? undefined : URL.parse(origin)?.protocol;
}

/**
 * Cookies are Secure unless the request is known to be plain http (local development).
 * An unknown protocol counts as secure, so a mistake can only make a cookie stricter.
 */
export function isSecureRequest(hints: SecureCookieHints): boolean {
  if (hints.forwardedProto !== null) {
    return hints.forwardedProto === HTTPS_SCHEME;
  }
  const protocol = hints.urlProtocol ?? protocolOfOrigin(hints.origin);
  return protocol === undefined || protocol === HTTPS_PROTOCOL;
}

export function readSecureCookieHints(
  headers: HeaderReader,
  urlProtocol?: string,
): SecureCookieHints {
  return {
    forwardedProto: headers.get(FORWARDED_PROTO_HEADER),
    origin: headers.get(ORIGIN_HEADER),
    urlProtocol,
  };
}

export function createActivityCookie(
  nowMs: number,
  isSecure: boolean,
): { name: string; value: string; options: AuthCookieOptions } {
  return {
    name: ACTIVITY_COOKIE_NAME,
    value: String(nowMs),
    options: { httpOnly: true, secure: isSecure, sameSite: "lax", path: COOKIE_PATH },
  };
}

export function createExpiredActivityCookie(isSecure: boolean) {
  const cookie = createActivityCookie(0, isSecure);
  return { ...cookie, value: "", options: { ...cookie.options, maxAge: EXPIRED_MAX_AGE_SECONDS } };
}
