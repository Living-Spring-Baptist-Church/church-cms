import { describe, expect, it } from "vitest";

import { ACTIVITY_COOKIE_NAME } from "@core/data/auth.data";

import {
  createActivityCookie,
  createExpiredActivityCookie,
  isSecureRequest,
  readSecureCookieHints,
} from "./cookies";

describe("isSecureRequest", () => {
  it("should follow the forwarded protocol first", () => {
    expect(isSecureRequest({ forwardedProto: "https", origin: null, urlProtocol: "http:" })).toBe(
      true,
    );
    expect(isSecureRequest({ forwardedProto: "http", origin: null, urlProtocol: "https:" })).toBe(
      false,
    );
  });

  it("should treat plain http on the request URL as not secure", () => {
    expect(isSecureRequest({ forwardedProto: null, origin: null, urlProtocol: "http:" })).toBe(
      false,
    );
  });

  it("should read the origin of a server action request", () => {
    expect(isSecureRequest({ forwardedProto: null, origin: "http://127.0.0.1:3000" })).toBe(false);
    expect(isSecureRequest({ forwardedProto: null, origin: "https://staff.example.org" })).toBe(
      true,
    );
  });

  it("should default to secure when nothing is known or the origin is unreadable", () => {
    expect(isSecureRequest({ forwardedProto: null, origin: null })).toBe(true);
    expect(isSecureRequest({ forwardedProto: null, origin: "not a url" })).toBe(true);
  });
});

describe("readSecureCookieHints", () => {
  it("should read the forwarded protocol and origin headers", () => {
    const headers = new Headers({ "x-forwarded-proto": "https", origin: "https://a.example" });

    expect(readSecureCookieHints(headers, "http:")).toEqual({
      forwardedProto: "https",
      origin: "https://a.example",
      urlProtocol: "http:",
    });
  });
});

describe("activity cookie", () => {
  it("should be httpOnly, SameSite Lax and carry the timestamp", () => {
    expect(createActivityCookie(42, true)).toEqual({
      name: ACTIVITY_COOKIE_NAME,
      value: "42",
      options: { httpOnly: true, secure: true, sameSite: "lax", path: "/" },
    });
  });

  it("should expire immediately when cleared", () => {
    const cookie = createExpiredActivityCookie(false);

    expect(cookie.value).toBe("");
    expect(cookie.options).toMatchObject({ maxAge: 0, secure: false, httpOnly: true });
  });
});
