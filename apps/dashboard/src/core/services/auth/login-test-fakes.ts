// Shared fakes for the login service tests. Not production code.
import type { AuthPort, AuthState, SignedInState } from "@lbc/providers";
import { vi } from "vitest";

import type { StaffRoleName } from "@core/auth/roles";
import type { Result } from "@core/errors/app-error";
import type { StaffProfile } from "@core/types/staff.types";

import { createLoginService } from "./login.service";

export const STAFF_ID = "staff-1";
export const CREDENTIALS = { email: "staff@example.org", password: "a-password" };
export const FACTOR_ID = "factor-1";

export function createSession(overrides: Partial<SignedInState> = {}): SignedInState {
  return {
    status: "signed_in",
    userId: STAFF_ID,
    email: CREDENTIALS.email,
    currentLevel: "aal1",
    nextLevel: "aal1",
    verifiedFactorId: null,
    accessToken: "token",
    ...overrides,
  };
}

export function createProfile(
  roles: readonly StaffRoleName[],
  isActive = true,
  hasUnrecognisedRole = false,
): StaffProfile {
  return { id: STAFF_ID, fullName: "Demo Staff", isActive, roles, hasUnrecognisedRole };
}

type SetupOptions = {
  readonly states?: readonly AuthState[];
  readonly profile?: Result<StaffProfile | null>;
  readonly signIn?: Awaited<ReturnType<AuthPort["signInWithPassword"]>>;
  readonly verify?: Awaited<ReturnType<AuthPort["verifyTotp"]>>;
  readonly audit?: Result<undefined>;
};

export const OK = { ok: true, data: undefined } as const;

export function setup(options: SetupOptions = {}) {
  const states = [...(options.states ?? [createSession()])];
  const auth = {
    signInWithPassword: vi.fn().mockResolvedValue(options.signIn ?? OK),
    getState: vi.fn(() => Promise.resolve(states.length > 1 ? states.shift() : states[0])),
    startTotpEnrolment: vi.fn().mockResolvedValue({
      ok: true,
      data: { factorId: FACTOR_ID, qrCodeDataUri: "data:", secret: "S" },
    }),
    listUnverifiedTotpFactorIds: vi.fn().mockResolvedValue({ ok: true, data: [FACTOR_ID] }),
    verifyTotp: vi.fn().mockResolvedValue(options.verify ?? OK),
    signOut: vi.fn().mockResolvedValue(OK),
  } satisfies Record<keyof AuthPort, unknown>;
  const loadStaffProfile = vi
    .fn()
    .mockResolvedValue(options.profile ?? { ok: true, data: createProfile(["usher"]) });
  const recordLogin = vi.fn().mockResolvedValue(options.audit ?? OK);
  const service = createLoginService({
    auth: auth as unknown as AuthPort,
    loadStaffProfile,
    recordLogin,
  });
  return { service, auth, loadStaffProfile, recordLogin };
}
