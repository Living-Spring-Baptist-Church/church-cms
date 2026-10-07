import { describe, expect, it } from "vitest";

import { ROUTES } from "@core/data/routes.data";

import { decideAccess, isPublicRoute, type AccessRequest } from "./access-policy";

const SIGNED_IN: AccessRequest = {
  pathname: "/members",
  isSignedIn: true,
  isIdleExpired: false,
  currentLevel: "aal1",
  nextLevel: "aal1",
};

describe("decideAccess", () => {
  it("should send a visitor without a session to the login page", () => {
    expect(decideAccess({ ...SIGNED_IN, isSignedIn: false })).toEqual({
      kind: "redirect_to_login",
    });
  });

  it("should let a visitor without a session open the login page", () => {
    expect(decideAccess({ ...SIGNED_IN, pathname: ROUTES.login, isSignedIn: false })).toEqual({
      kind: "allow",
    });
  });

  it("should let a signed in user without two-factor through at aal1", () => {
    expect(decideAccess(SIGNED_IN)).toEqual({ kind: "allow" });
  });

  it("should hold a user who owns an authenticator app at aal1 until they enter a code", () => {
    expect(decideAccess({ ...SIGNED_IN, nextLevel: "aal2" })).toEqual({
      kind: "redirect_to_login",
    });
  });

  it("should let a user with an authenticator app through at aal2", () => {
    expect(decideAccess({ ...SIGNED_IN, currentLevel: "aal2", nextLevel: "aal2" })).toEqual({
      kind: "allow",
    });
  });

  it("should still show the login page to a user who owes a code", () => {
    expect(decideAccess({ ...SIGNED_IN, pathname: ROUTES.login, nextLevel: "aal2" })).toEqual({
      kind: "allow",
    });
  });

  it.each([ROUTES.home, ROUTES.login, "/members"])(
    "should expire an idle session on %s",
    (pathname) => {
      expect(decideAccess({ ...SIGNED_IN, pathname, isIdleExpired: true })).toEqual({
        kind: "expire",
      });
    },
  );

  it("should not expire anything for a visitor without a session", () => {
    expect(decideAccess({ ...SIGNED_IN, isSignedIn: false, isIdleExpired: true })).toEqual({
      kind: "redirect_to_login",
    });
  });
});

describe("isPublicRoute", () => {
  it("should name the login and session end routes and nothing else", () => {
    expect(isPublicRoute(ROUTES.login)).toBe(true);
    expect(isPublicRoute(ROUTES.sessionEnd)).toBe(true);
    expect(isPublicRoute(ROUTES.home)).toBe(false);
    expect(isPublicRoute("/login/other")).toBe(false);
  });
});
