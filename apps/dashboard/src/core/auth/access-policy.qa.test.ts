import { describe, expect, it } from "vitest";

import { ROUTES } from "@core/data/routes.data";

import { decideAccess, isPublicRoute, type AccessRequest } from "./access-policy";

const SIGNED_OUT: AccessRequest = {
  pathname: "/",
  isSignedIn: false,
  isIdleExpired: false,
  currentLevel: "aal1",
  nextLevel: "aal1",
};

// Next.js can hand the proxy raw paths, so only the exact public paths may open without a session.
const LOOK_ALIKE_PATHS = [
  "/login/",
  "/Login",
  "/LOGIN",
  "//login",
  "/login/extra",
  "/login%2F",
  "/%6cogin",
  "/login.json",
  "/session/end/",
  "/Session/End",
  "/session/end/../../account/security",
  "/account/security",
  "/Account/Security",
  "//account/security",
  "/account/security/",
  "/%61ccount/security",
  "/robots.txt",
  "/api/anything",
  "/not-found",
  "/_not-found",
  "/error",
];

describe("decideAccess route table (QA)", () => {
  it.each(LOOK_ALIKE_PATHS)(
    "should send a visitor without a session away from %s to the login page",
    (pathname) => {
      expect(decideAccess({ ...SIGNED_OUT, pathname })).toEqual({ kind: "redirect_to_login" });
    },
  );

  it.each(LOOK_ALIKE_PATHS)("should not treat %s as a public route", (pathname) => {
    expect(isPublicRoute(pathname)).toBe(false);
  });

  it.each([ROUTES.login, ROUTES.sessionEnd])(
    "should let a visitor without a session open exactly %s",
    (pathname) => {
      expect(decideAccess({ ...SIGNED_OUT, pathname })).toEqual({ kind: "allow" });
    },
  );

  it.each(LOOK_ALIKE_PATHS)(
    "should keep a signed in user who owes a code away from %s",
    (pathname) => {
      const decision = decideAccess({
        ...SIGNED_OUT,
        pathname,
        isSignedIn: true,
        currentLevel: "aal1",
        nextLevel: "aal2",
      });

      expect(decision).toEqual(
        isPublicRoute(pathname) ? { kind: "allow" } : { kind: "redirect_to_login" },
      );
    },
  );

  it.each([ROUTES.login, ROUTES.sessionEnd, ROUTES.home, "/Account/Security", "//x"])(
    "should expire an idle signed in session on %s before any routing",
    (pathname) => {
      expect(
        decideAccess({ ...SIGNED_OUT, pathname, isSignedIn: true, isIdleExpired: true }),
      ).toEqual({ kind: "expire" });
    },
  );

  it("should never expire a session for a visitor who is not signed in", () => {
    expect(decideAccess({ ...SIGNED_OUT, pathname: ROUTES.login, isIdleExpired: true })).toEqual({
      kind: "allow",
    });
  });

  it("should let a user at aal2 through every non public path", () => {
    const request = {
      ...SIGNED_OUT,
      isSignedIn: true,
      currentLevel: "aal2",
      nextLevel: "aal2",
    } as const;

    expect(decideAccess({ ...request, pathname: "/members" })).toEqual({ kind: "allow" });
    expect(decideAccess({ ...request, pathname: "/Account/Security" })).toEqual({ kind: "allow" });
  });
});
