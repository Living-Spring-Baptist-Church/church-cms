import { describe, expect, it } from "vitest";

import {
  HSTS_MAX_AGE_SECONDS,
  createSecurityHeaderRoutes,
  createSecurityHeaders,
} from "./security-headers";

function findHeaderValue(headerKey: string) {
  return createSecurityHeaders().find((header) => header.key === headerKey)?.value;
}

describe("createSecurityHeaders", () => {
  it("should force HTTPS for two years including subdomains, without preload", () => {
    const hstsValue = findHeaderValue("Strict-Transport-Security");

    expect(hstsValue).toBe("max-age=63072000; includeSubDomains");
    expect(HSTS_MAX_AGE_SECONDS).toBe(63_072_000);
    expect(hstsValue).not.toContain("preload");
  });

  it("should forbid framing with both X-Frame-Options and frame-ancestors", () => {
    expect(findHeaderValue("X-Frame-Options")).toBe("DENY");
    expect(findHeaderValue("Content-Security-Policy")).toContain("frame-ancestors 'none'");
  });

  it("should restrict base, form, object in the content security policy", () => {
    const policy = findHeaderValue("Content-Security-Policy");

    expect(policy).toContain("base-uri 'self'");
    expect(policy).toContain("form-action 'self'");
    expect(policy).toContain("object-src 'none'");
  });

  it("should not restrict scripts, so Next.js inline hydration scripts keep working", () => {
    const policy = findHeaderValue("Content-Security-Policy");

    expect(policy).not.toContain("script-src");
    expect(policy).not.toContain("default-src");
  });

  it("should deny camera, microphone and geolocation", () => {
    expect(findHeaderValue("Permissions-Policy")).toBe("camera=(), microphone=(), geolocation=()");
  });

  it("should stop MIME sniffing and limit the referrer", () => {
    expect(findHeaderValue("X-Content-Type-Options")).toBe("nosniff");
    expect(findHeaderValue("Referrer-Policy")).toBe("strict-origin-when-cross-origin");
  });
});

describe("createSecurityHeaderRoutes", () => {
  it("should apply every header to every path in one route", () => {
    const routes = createSecurityHeaderRoutes();

    expect(routes).toHaveLength(1);
    expect(routes[0]?.source).toBe("/(.*)");
    expect(routes[0]?.headers).toEqual(createSecurityHeaders());
  });
});
