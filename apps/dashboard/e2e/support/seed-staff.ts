import { fileURLToPath } from "node:url";

// Seed accounts from supabase/seed.sql. The password is the public local dev password from
// supabase/seed.local-auth.sql (README, "Signing in locally"). It protects nothing.
export const LOCAL_DEV_PASSWORD = "Dev-Only-Passw0rd";

export const SEED_STAFF = {
  pastor: { email: "pastor@demo.church", fullName: "Demo Pastor", needsTwoFactor: true },
  treasurer: { email: "treasurer@demo.church", fullName: "Demo Treasurer", needsTwoFactor: true },
  secretary: { email: "secretary@demo.church", fullName: "Demo Secretary", needsTwoFactor: false },
  usher: { email: "usher@demo.church", fullName: "Demo Usher", needsTwoFactor: false },
  departmentHead: {
    email: "department-head@demo.church",
    fullName: "Demo Department Head",
    needsTwoFactor: false,
  },
  contentEditor: {
    email: "content-editor@demo.church",
    fullName: "Demo Content Editor",
    needsTwoFactor: false,
  },
} as const;

export type SeedStaffKey = keyof typeof SEED_STAFF;

export const SEED_STAFF_KEYS = Object.keys(SEED_STAFF) as readonly SeedStaffKey[];

const AUTH_STATE_DIRECTORY = fileURLToPath(new URL("../.auth/", import.meta.url));

/** Where the setup project stores each role's signed-in browser state. Gitignored in e2e/.gitignore. */
export function authStatePath(staffKey: SeedStaffKey): string {
  return `${AUTH_STATE_DIRECTORY}${staffKey}.json`;
}
