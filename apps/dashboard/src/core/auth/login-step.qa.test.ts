import { describe, expect, it } from "vitest";

import { determineLoginStep, type LoginStep } from "./login-step";
import { STAFF_ROLES, profileRequiresMfa, type StaffRoleName } from "./roles";

type Case = {
  readonly level: "aal1" | "aal2";
  readonly hasApp: boolean;
  readonly roles: readonly StaffRoleName[];
  readonly hasUnrecognisedRole: boolean;
};

function expectedStep({ level, hasApp, roles, hasUnrecognisedRole }: Case): LoginStep {
  if (level === "aal2") {
    return "complete";
  }
  if (hasApp) {
    return "verify_code";
  }
  return profileRequiresMfa({ roles, hasUnrecognisedRole }) ? "enrol" : "complete";
}

const ROLE_SETS: readonly (readonly StaffRoleName[])[] = [
  ...STAFF_ROLES.map((role) => [role] as const),
  ["usher", "pastor"],
  ["usher", "secretary"],
  ["content_editor", "department_head"],
];

describe("determineLoginStep matrix (QA)", () => {
  const cases: Case[] = [];
  for (const level of ["aal1", "aal2"] as const) {
    for (const hasApp of [true, false]) {
      for (const hasUnrecognisedRole of [true, false]) {
        for (const roles of ROLE_SETS) {
          cases.push({ level, hasApp, roles, hasUnrecognisedRole });
        }
      }
    }
  }

  it.each(cases)(
    "should give the expected step for $level app=$hasApp unknown=$hasUnrecognisedRole roles=$roles",
    (testCase) => {
      const step = determineLoginStep({
        session: {
          currentLevel: testCase.level,
          verifiedFactorId: testCase.hasApp ? "factor-1" : null,
        },
        profile: { roles: testCase.roles, hasUnrecognisedRole: testCase.hasUnrecognisedRole },
      });

      expect(step).toBe(expectedStep(testCase));
    },
  );

  it("should never complete a login at aal1 for a two-factor role", () => {
    for (const role of ["super_admin", "pastor", "treasurer"] as const) {
      for (const hasApp of [true, false]) {
        const step = determineLoginStep({
          session: { currentLevel: "aal1", verifiedFactorId: hasApp ? "f" : null },
          profile: { roles: [role], hasUnrecognisedRole: false },
        });

        expect(step).not.toBe("complete");
      }
    }
  });

  it("should never ask a user at aal2 for another step", () => {
    const step = determineLoginStep({
      session: { currentLevel: "aal2", verifiedFactorId: "f" },
      profile: { roles: [], hasUnrecognisedRole: true },
    });

    expect(step).toBe("complete");
  });
});
