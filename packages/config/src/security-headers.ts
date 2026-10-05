const SECONDS_PER_YEAR = 31_536_000;
const HSTS_YEARS = 2;
export const HSTS_MAX_AGE_SECONDS = SECONDS_PER_YEAR * HSTS_YEARS;

const ALL_PATHS_SOURCE = "/(.*)";

// Conservative on purpose: no script-src or connect-src, because Next.js hydration relies on inline
// scripts and a nonce policy needs request middleware. See README, "Security headers".
const CONTENT_SECURITY_POLICY_DIRECTIVES = [
  "frame-ancestors 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "object-src 'none'",
] as const;

// Nothing in either app needs a sensor. Re-enable a feature here only when a ticket needs it.
const DENIED_BROWSER_FEATURES = ["camera", "microphone", "geolocation"] as const;

export type SecurityHeader = {
  readonly key: string;
  readonly value: string;
};

export type SecurityHeaderRoute = {
  readonly source: string;
  readonly headers: SecurityHeader[];
};

function buildPermissionsPolicy(deniedFeatures: readonly string[]) {
  return deniedFeatures.map((feature) => `${feature}=()`).join(", ");
}

export function createSecurityHeaders(): SecurityHeader[] {
  return [
    {
      key: "Strict-Transport-Security",
      value: `max-age=${String(HSTS_MAX_AGE_SECONDS)}; includeSubDomains`,
    },
    { key: "Content-Security-Policy", value: CONTENT_SECURITY_POLICY_DIRECTIVES.join("; ") },
    { key: "X-Frame-Options", value: "DENY" },
    { key: "X-Content-Type-Options", value: "nosniff" },
    { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
    { key: "Permissions-Policy", value: buildPermissionsPolicy(DENIED_BROWSER_FEATURES) },
  ];
}

// Mutable arrays because the Next.js headers() type is mutable.
/** The value for `headers()` in next.config.ts of both apps. */
export function createSecurityHeaderRoutes(): SecurityHeaderRoute[] {
  return [{ source: ALL_PATHS_SOURCE, headers: createSecurityHeaders() }];
}
