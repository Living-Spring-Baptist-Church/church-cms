import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { ACTIVITY_COOKIE_NAME } from "@core/data/auth.data";

import {
  clearActivity,
  createRequestAuth,
  createRequestLoginService,
  isRequestSecure,
  readLastActivity,
  readRequestId,
  touchActivity,
} from "./request-context";

type CapturedOptions = {
  isSecureCookie: boolean;
  totpIssuer: string;
  cookieStore: {
    getAll: () => unknown;
    setAll: (cookies: { name: string; value: string; options: object }[]) => void;
  };
};

const mocks = vi.hoisted(() => ({
  cookieJar: { getAll: vi.fn(), get: vi.fn(), set: vi.fn() },
  requestHeaders: new Map<string, string>(),
  createSupabaseAuth: vi.fn(),
  fetchStaffProfile: vi.fn(),
  recordLogin: vi.fn(),
}));

vi.mock("next/headers", () => ({
  cookies: () => Promise.resolve(mocks.cookieJar),
  headers: () => Promise.resolve({ get: (name: string) => mocks.requestHeaders.get(name) ?? null }),
}));
vi.mock("@lbc/providers", () => ({ createSupabaseAuth: mocks.createSupabaseAuth }));
vi.mock("@core/auth/session-client", () => ({ createSessionGraphqlClient: () => ({}) }));
vi.mock("@core/services/staff/staff.service", () => ({
  fetchStaffProfile: mocks.fetchStaffProfile,
}));
vi.mock("@core/services/audit/audit.service", () => ({ recordLogin: mocks.recordLogin }));

function capturedOptions(): CapturedOptions {
  return mocks.createSupabaseAuth.mock.calls.at(-1)?.[0] as CapturedOptions;
}

beforeEach(() => {
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "http://127.0.0.1:54321");
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", "anon-key");
  mocks.requestHeaders.clear();
  mocks.createSupabaseAuth.mockReturnValue({ getState: vi.fn(), signOut: vi.fn() });
});

afterEach(() => {
  vi.unstubAllEnvs();
  vi.clearAllMocks();
});

describe("createRequestAuth", () => {
  it("should read the session from the request cookies and name the app in the authenticator", async () => {
    mocks.cookieJar.getAll.mockReturnValue([{ name: "a", value: "1" }]);

    await createRequestAuth("writable");

    expect(capturedOptions().cookieStore.getAll()).toEqual([{ name: "a", value: "1" }]);
    expect(capturedOptions().totpIssuer).toBe("Living Spring Baptist Church");
  });

  it("should write refreshed session cookies when the request may write", async () => {
    await createRequestAuth("writable");

    capturedOptions().cookieStore.setAll([{ name: "sb", value: "t", options: { path: "/" } }]);

    expect(mocks.cookieJar.set).toHaveBeenCalledWith("sb", "t", { path: "/" });
  });

  it("should leave cookies alone for a server component, which cannot write them", async () => {
    await createRequestAuth("read_only");

    capturedOptions().cookieStore.setAll([{ name: "sb", value: "t", options: {} }]);

    expect(mocks.cookieJar.set).not.toHaveBeenCalled();
  });

  it("should mark cookies Secure unless the request is plain http", async () => {
    mocks.requestHeaders.set("origin", "http://127.0.0.1:3000");
    await createRequestAuth("writable");
    expect(capturedOptions().isSecureCookie).toBe(false);

    mocks.requestHeaders.set("x-forwarded-proto", "https");
    await createRequestAuth("writable");
    expect(capturedOptions().isSecureCookie).toBe(true);
    await expect(isRequestSecure()).resolves.toBe(true);
  });
});

describe("createRequestLoginService", () => {
  it("should load the profile and record the login as the signed in user", async () => {
    const getState = vi.fn().mockResolvedValue({
      status: "signed_in",
      userId: "u1",
      email: "a@b.c",
      currentLevel: "aal1",
      nextLevel: "aal1",
      verifiedFactorId: null,
      accessToken: "t",
    });
    mocks.createSupabaseAuth.mockReturnValue({
      getState,
      signInWithPassword: vi.fn().mockResolvedValue({ ok: true, data: undefined }),
      signOut: vi.fn(),
    });
    mocks.fetchStaffProfile.mockResolvedValue({
      ok: true,
      data: {
        id: "u1",
        fullName: "A",
        isActive: true,
        roles: ["usher"],
        hasUnrecognisedRole: false,
      },
    });
    mocks.recordLogin.mockResolvedValue({ ok: true, data: undefined });

    const service = await createRequestLoginService("writable");
    await expect(service.signIn({ email: "a@b.c", password: "x" })).resolves.toEqual({
      ok: true,
      data: "complete",
    });

    expect(mocks.fetchStaffProfile).toHaveBeenCalledWith({}, "u1");
    expect(mocks.recordLogin).toHaveBeenCalledWith(
      expect.objectContaining({ staffId: "u1", method: "password" }),
    );
  });
});

describe("activity cookie", () => {
  it("should read the last activity as a number, or null when missing", async () => {
    mocks.cookieJar.get.mockReturnValueOnce({ value: "1700000000000" });
    await expect(readLastActivity()).resolves.toBe(1_700_000_000_000);

    mocks.cookieJar.get.mockReturnValueOnce(undefined);
    await expect(readLastActivity()).resolves.toBeNull();
  });

  it("should set an httpOnly activity cookie with the time", async () => {
    await touchActivity(42);

    expect(mocks.cookieJar.set).toHaveBeenCalledWith(
      ACTIVITY_COOKIE_NAME,
      "42",
      expect.objectContaining({ httpOnly: true, sameSite: "lax" }),
    );
  });

  it("should expire the activity cookie when cleared", async () => {
    await clearActivity();

    expect(mocks.cookieJar.set).toHaveBeenCalledWith(
      ACTIVITY_COOKIE_NAME,
      "",
      expect.objectContaining({ maxAge: 0 }),
    );
  });
});

describe("readRequestId", () => {
  it("should return the id the proxy attached, or undefined", async () => {
    mocks.requestHeaders.set("x-request-id", "req-1");
    await expect(readRequestId()).resolves.toBe("req-1");

    mocks.requestHeaders.clear();
    await expect(readRequestId()).resolves.toBeUndefined();
  });
});
