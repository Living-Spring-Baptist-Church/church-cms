import type { SeedStaffKey } from "./seed-staff";

// What each seed role must see on the overview, from the PRD permission matrix (docs/prd.md) and
// OVR-01 / OVR-02. Written out by hand on purpose, so the test does not reuse the app's own data.
export const ALL_MODULES = [
  "Overview",
  "Members",
  "Attendance",
  "Programs",
  "Finance",
  "Messaging",
  "Reports",
  "Content",
  "Audit trail",
  "Settings",
] as const;

export const ALL_CARDS = [
  "Last Sunday's attendance",
  "New visitors this month",
  "Month-to-date giving",
] as const;

export const ALL_QUICK_ACTIONS = ["Record attendance", "Record offering", "Add member"] as const;

export type RoleExpectation = {
  readonly modules: readonly (typeof ALL_MODULES)[number][];
  readonly cards: readonly (typeof ALL_CARDS)[number][];
  readonly quickActions: readonly (typeof ALL_QUICK_ACTIONS)[number][];
  readonly roleLabel: string;
};

export const ROLE_EXPECTATIONS: Readonly<Record<SeedStaffKey, RoleExpectation>> = {
  usher: {
    roleLabel: "Usher",
    modules: ["Overview", "Members", "Attendance"],
    cards: ["Last Sunday's attendance"],
    quickActions: ["Record attendance"],
  },
  secretary: {
    roleLabel: "Secretary",
    modules: ["Overview", "Members", "Attendance", "Programs", "Messaging", "Reports", "Content"],
    cards: ["Last Sunday's attendance", "New visitors this month"],
    quickActions: ["Record attendance", "Add member"],
  },
  pastor: {
    roleLabel: "Pastor",
    modules: [
      "Overview",
      "Members",
      "Attendance",
      "Programs",
      "Finance",
      "Messaging",
      "Reports",
      "Content",
      "Audit trail",
    ],
    cards: ["Last Sunday's attendance", "New visitors this month"],
    quickActions: [],
  },
  treasurer: {
    roleLabel: "Treasurer",
    modules: ["Overview", "Members", "Finance", "Reports"],
    cards: [],
    quickActions: ["Record offering"],
  },
  departmentHead: {
    roleLabel: "Department head",
    modules: ["Overview", "Members", "Attendance", "Programs", "Messaging", "Reports", "Content"],
    cards: [],
    quickActions: [],
  },
  contentEditor: {
    roleLabel: "Content editor",
    modules: ["Overview", "Content"],
    cards: [],
    quickActions: [],
  },
};
