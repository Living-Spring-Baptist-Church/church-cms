import { describe, expect, it } from "vitest";

import { filterByRoles, type StaffRoleName } from "@core/auth/roles";

import { NAVIGATION_MODULES } from "./navigation.data";

function moduleIdsFor(roles: readonly StaffRoleName[]): readonly string[] {
  return filterByRoles(NAVIGATION_MODULES, roles).map((module) => module.id);
}

describe("NAVIGATION_MODULES", () => {
  it("should show an usher the overview, members and attendance only", () => {
    expect(moduleIdsFor(["usher"])).toEqual(["overview", "members", "attendance"]);
  });

  it("should show a treasurer the overview, members, finance and reports, but not attendance", () => {
    expect(moduleIdsFor(["treasurer"])).toEqual(["overview", "members", "finance", "reports"]);
  });

  it("should show a secretary every module except finance, audit trail and settings", () => {
    expect(moduleIdsFor(["secretary"])).toEqual([
      "overview",
      "members",
      "attendance",
      "programs",
      "messaging",
      "reports",
      "content",
    ]);
  });

  it("should show a pastor every module except settings", () => {
    expect(moduleIdsFor(["pastor"])).not.toContain("settings");
    expect(moduleIdsFor(["pastor"])).toContain("audit");
    expect(moduleIdsFor(["pastor"])).toContain("finance");
  });

  it("should show a super admin every module", () => {
    expect(moduleIdsFor(["super_admin"])).toEqual(NAVIGATION_MODULES.map((module) => module.id));
  });

  it("should show a content editor the overview and content only", () => {
    expect(moduleIdsFor(["content_editor"])).toEqual(["overview", "content"]);
  });

  it("should show a department head the modules for their own department, not finance or audit", () => {
    expect(moduleIdsFor(["department_head"])).not.toContain("finance");
    expect(moduleIdsFor(["department_head"])).not.toContain("audit");
    expect(moduleIdsFor(["department_head"])).toContain("programs");
  });

  it("should show a staff member holding several roles every module any of those roles may use", () => {
    expect(moduleIdsFor(["usher", "treasurer"])).toEqual([
      "overview",
      "members",
      "attendance",
      "finance",
      "reports",
    ]);
  });
});
