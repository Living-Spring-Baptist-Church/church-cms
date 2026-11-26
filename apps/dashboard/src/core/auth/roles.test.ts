import { describe, expect, it } from "vitest";

import { FINANCE_ROLES, filterByRoles, hasRole, type StaffRoleName } from "./roles";

describe("hasRole", () => {
  it("should be true when a held role is in the allowed list", () => {
    expect(hasRole(["usher", "secretary"], ["secretary"])).toBe(true);
  });

  it("should be false when no held role is in the allowed list", () => {
    expect(hasRole(["usher"], ["pastor", "treasurer"])).toBe(false);
  });

  it("should be false for a staff member with no roles", () => {
    expect(hasRole([], ["usher"])).toBe(false);
  });
});

describe("FINANCE_ROLES", () => {
  it("should allow the pastor, the treasurer and the super admin to see finance", () => {
    expect(FINANCE_ROLES).toEqual(["super_admin", "pastor", "treasurer"]);
  });
});

describe("filterByRoles", () => {
  const ENTRIES: readonly {
    readonly id: string;
    readonly allowedRoles: readonly StaffRoleName[];
  }[] = [
    { id: "everyone", allowedRoles: ["usher", "pastor"] },
    { id: "leaders", allowedRoles: ["pastor"] },
    { id: "admins", allowedRoles: ["super_admin"] },
  ];

  it("should keep only the entries that a held role may use", () => {
    expect(filterByRoles(ENTRIES, ["usher"]).map((entry) => entry.id)).toEqual(["everyone"]);
  });

  it("should keep every entry that any of several held roles may use", () => {
    expect(filterByRoles(ENTRIES, ["usher", "super_admin"]).map((entry) => entry.id)).toEqual([
      "everyone",
      "admins",
    ]);
  });

  it("should keep nothing when the staff member holds no role", () => {
    expect(filterByRoles(ENTRIES, [])).toEqual([]);
  });
});
