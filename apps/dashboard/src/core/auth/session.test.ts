import { beforeEach, describe, expect, it, vi } from "vitest";

import { createAppError } from "@core/errors/app-error";
import type { StaffProfile } from "@core/types/staff.types";

import { requireStaff } from "./session";

const mocks = vi.hoisted(() => ({
  getState: vi.fn(),
  fetchStaffProfile: vi.fn(),
  error: vi.fn(),
}));

vi.mock("react", async (importOriginal) => ({
  ...(await importOriginal<typeof import("react")>()),
  cache: <TFunction>(callback: TFunction) => callback,
}));
vi.mock("next/navigation", () => ({
  redirect: (destination: string) => {
    throw new Error(`REDIRECT ${destination}`);
  },
}));
vi.mock("@core/auth/request-context", () => ({
  createRequestAuth: () => Promise.resolve({ getState: mocks.getState }),
}));
vi.mock("@core/auth/session-client", () => ({ createSessionGraphqlClient: () => ({}) }));
vi.mock("@core/services/staff/staff.service", () => ({
  fetchStaffProfile: mocks.fetchStaffProfile,
}));
vi.mock("@config/logger", () => ({ logger: { error: mocks.error } }));

function signedIn(overrides: Record<string, unknown> = {}) {
  return {
    status: "signed_in",
    userId: "u1",
    email: "staff@example.org",
    currentLevel: "aal1",
    nextLevel: "aal1",
    verifiedFactorId: null,
    accessToken: "token",
    ...overrides,
  };
}

function profile(overrides: Partial<StaffProfile> = {}) {
  return {
    ok: true,
    data: {
      id: "u1",
      fullName: "Demo Staff",
      isActive: true,
      roles: ["usher"],
      hasUnrecognisedRole: false,
      ...overrides,
    },
  };
}

beforeEach(() => {
  vi.clearAllMocks();
  mocks.getState.mockResolvedValue(signedIn());
  mocks.fetchStaffProfile.mockResolvedValue(profile());
});

describe("requireStaff", () => {
  it("should send a visitor without a session to the login page", async () => {
    mocks.getState.mockResolvedValue({ status: "signed_out" });

    await expect(requireStaff()).rejects.toThrow("REDIRECT /login");
    expect(mocks.fetchStaffProfile).not.toHaveBeenCalled();
  });

  it("should admit an active staff member whose role does not need two-factor", async () => {
    await expect(requireStaff()).resolves.toMatchObject({
      profile: { fullName: "Demo Staff" },
      email: "staff@example.org",
      hasVerifiedFactor: false,
    });
  });

  it("should admit a pastor at aal2", async () => {
    mocks.getState.mockResolvedValue(
      signedIn({ currentLevel: "aal2", nextLevel: "aal2", verifiedFactorId: "f1" }),
    );
    mocks.fetchStaffProfile.mockResolvedValue(profile({ roles: ["pastor"] }));

    await expect(requireStaff()).resolves.toMatchObject({ hasVerifiedFactor: true });
  });

  it("should hold a pastor at aal1 without an app on the login page", async () => {
    mocks.fetchStaffProfile.mockResolvedValue(profile({ roles: ["pastor"] }));

    await expect(requireStaff()).rejects.toThrow("REDIRECT /login");
  });

  it("should hold a user who still owes a code on the login page", async () => {
    mocks.getState.mockResolvedValue(signedIn({ nextLevel: "aal2", verifiedFactorId: "f1" }));

    await expect(requireStaff()).rejects.toThrow("REDIRECT /login");
  });

  it.each([
    ["a deactivated account", profile({ isActive: false })],
    ["a staff member with no role", profile({ roles: [] })],
    ["a missing staff row", { ok: true, data: null }],
  ])("should end the session of %s", async (_label, result) => {
    mocks.fetchStaffProfile.mockResolvedValue(result);

    await expect(requireStaff()).rejects.toThrow("REDIRECT /session/end");
  });

  it("should fail closed for a role the app does not know when no code was entered", async () => {
    mocks.fetchStaffProfile.mockResolvedValue(profile({ roles: [], hasUnrecognisedRole: true }));

    await expect(requireStaff()).rejects.toThrow("REDIRECT /login");
  });

  it("should log the technical detail and show only the plain message when the profile fails", async () => {
    mocks.fetchStaffProfile.mockResolvedValue({
      ok: false,
      error: createAppError("network", "ECONNREFUSED"),
    });

    await expect(requireStaff()).rejects.toThrow(
      "We could not reach the server. Check your connection and try again.",
    );
    expect(mocks.error).toHaveBeenCalledWith(
      "Could not load the staff profile",
      expect.objectContaining({ detail: "ECONNREFUSED" }),
    );
  });
});
