import { describe, expect, it } from "vitest";

import { determineLoginStep } from "./login-step";
import {
  MFA_REQUIRED_ROLES,
  STAFF_ROLES,
  hasAnyRole,
  hasRole,
  isStaffRoleName,
  profileRequiresMfa,
  requiresMfa,
  type StaffRoleName,
} from "./roles";

function holder(roles: readonly StaffRoleName[], hasUnrecognisedRole = false) {
  return { roles, hasUnrecognisedRole };
}

const NO_APP = { currentLevel: "aal1", verifiedFactorId: null } as const;

describe("determineLoginStep", () => {
  it.each(MFA_REQUIRED_ROLES)("should force enrolment for %s without an app", (role) => {
    expect(determineLoginStep({ session: NO_APP, profile: holder([role]) })).toBe("enrol");
  });

  it("should complete the login of a role without the requirement", () => {
    expect(determineLoginStep({ session: NO_APP, profile: holder(["usher"]) })).toBe("complete");
  });

  it("should force enrolment when any one of several roles requires it", () => {
    expect(determineLoginStep({ session: NO_APP, profile: holder(["usher", "treasurer"]) })).toBe(
      "enrol",
    );
  });

  it("should ask for a code when an app exists, even for optional roles", () => {
    const session = { currentLevel: "aal1", verifiedFactorId: "f1" } as const;
    expect(determineLoginStep({ session, profile: holder(["usher"]) })).toBe("verify_code");
  });

  it("should be complete once the session is at aal2", () => {
    const session = { currentLevel: "aal2", verifiedFactorId: "f1" } as const;
    expect(determineLoginStep({ session, profile: holder(["pastor"]) })).toBe("complete");
  });

  it("should complete the login of a user with no roles", () => {
    expect(determineLoginStep({ session: NO_APP, profile: holder([]) })).toBe("complete");
  });
});

describe("fail closed on roles", () => {
  it("should force enrolment for a role this app does not know yet", () => {
    expect(determineLoginStep({ session: NO_APP, profile: holder(["usher"], true) })).toBe("enrol");
    expect(profileRequiresMfa(holder([], true))).toBe(true);
  });

  it("should treat a staff row with no role at all as no access", () => {
    expect(hasAnyRole(holder([]))).toBe(false);
    expect(hasAnyRole(holder(["usher"]))).toBe(true);
    expect(hasAnyRole(holder([], true))).toBe(true);
  });
});

describe("roles", () => {
  it("should require two-factor for super admin, pastor and treasurer only", () => {
    expect(MFA_REQUIRED_ROLES).toEqual(["super_admin", "pastor", "treasurer"]);
    expect(STAFF_ROLES.filter((role) => requiresMfa([role]))).toEqual(MFA_REQUIRED_ROLES);
  });

  it("should recognise role names", () => {
    expect(isStaffRoleName("pastor")).toBe(true);
    expect(isStaffRoleName("visitor")).toBe(false);
  });

  it("should match any held role against the allowed ones", () => {
    expect(hasRole(["usher", "secretary"], ["secretary"])).toBe(true);
    expect(hasRole(["usher"], ["secretary"])).toBe(false);
    expect(hasRole([], ["secretary"])).toBe(false);
  });
});
