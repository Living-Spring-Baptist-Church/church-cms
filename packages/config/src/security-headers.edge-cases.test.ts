import { describe, expect, it } from "vitest";

import {
  HSTS_MAX_AGE_SECONDS,
  createSecurityHeaderRoutes,
  createSecurityHeaders,
} from "./security-headers";

const ONE_YEAR_SECONDS = 31_536_000;
const EM_DASH_CODE_POINT = 0x2014;
const EM_DASH = String.fromCodePoint(EM_DASH_CODE_POINT);
const REQUIRED_HEADER_NAMES = [
  "Strict-Transport-Security",
  "Content-Security-Policy",
  "X-Frame-Options",
  "X-Content-Type-Options",
  "Referrer-Policy",
  "Permissions-Policy",
];

describe("security header edge cases", () => {
  it("should list each header name exactly once when headers are built", () => {
    const headerNames = createSecurityHeaders().map((header) => header.key.toLowerCase());

    expect(new Set(headerNames).size).toBe(headerNames.length);
    expect(createSecurityHeaders().map((header) => header.key)).toEqual(REQUIRED_HEADER_NAMES);
  });

  it("should contain no newline, carriage return or em dash in any header when built", () => {
    createSecurityHeaders().forEach((header) => {
      expect(`${header.key}${header.value}`).not.toMatch(/[\r\n]/);
      expect(`${header.key}${header.value}`).not.toContain(EM_DASH);
      expect(header.value.trim()).toBe(header.value);
      expect(header.value.length).toBeGreaterThan(0);
    });
  });

  it("should keep HSTS at one year or more with subdomains when built", () => {
    const hstsValue = createSecurityHeaders().find(
      (header) => header.key === "Strict-Transport-Security",
    )?.value;

    expect(HSTS_MAX_AGE_SECONDS).toBeGreaterThanOrEqual(ONE_YEAR_SECONDS);
    expect(hstsValue).toMatch(/^max-age=\d+; includeSubDomains$/);
  });

  it("should return fresh arrays on every call so one app cannot mutate another", () => {
    const firstRoutes = createSecurityHeaderRoutes();
    firstRoutes[0]?.headers.pop();

    expect(createSecurityHeaderRoutes()[0]?.headers).toHaveLength(REQUIRED_HEADER_NAMES.length);
  });

  it("should match every path including nested and dotted paths when used as a source", () => {
    const source = createSecurityHeaderRoutes()[0]?.source ?? "";
    const pathPattern = new RegExp(`^${source}$`);

    ["", "a", "a/b/c", "_next/static/x.js", "icon.png", "a%20b", "caf%C3%A9/"].forEach((path) => {
      expect(pathPattern.test(`/${path}`)).toBe(true);
    });
  });
});
