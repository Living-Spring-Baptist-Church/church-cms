import { describe, expect, it, vi } from "vitest";

import { createSupabaseAuthPort } from "./supabase-auth.adapter";

const TOTP_ISSUER = "Test Church";
const FACTOR_ID = "factor-1";
const ACCESS_TOKEN = "access-token";
const FAILURE = { name: "AuthApiError", message: "rejected", status: 400, code: "some_code" };

type FakeOverrides = {
  readonly user?: Record<string, unknown>;
  readonly userError?: unknown;
  readonly levels?: { currentLevel: string | null; nextLevel: string | null };
  readonly levelError?: unknown;
  readonly session?: { access_token: string } | null;
  readonly factors?: readonly Record<string, unknown>[];
  readonly enrollResult?: { data: unknown; error: unknown };
  readonly verifyError?: unknown;
  readonly signInError?: unknown;
  readonly signOutError?: unknown;
};

const FAKE_DEFAULTS = {
  user: { id: "user-1", email: "staff@example.org", factors: [] },
  userError: null,
  levels: { currentLevel: "aal1", nextLevel: "aal1" },
  levelError: null,
  session: { access_token: ACCESS_TOKEN },
  factors: [],
  enrollResult: {
    data: { id: FACTOR_ID, totp: { qr_code: "<svg/>", secret: "SECRET" } },
    error: null,
  },
  verifyError: null,
  signInError: null,
  signOutError: null,
};

function createFakeAuth(overrides: FakeOverrides = {}) {
  const fake = { ...FAKE_DEFAULTS, ...overrides };
  const unenroll = vi.fn().mockResolvedValue({ data: null, error: null });
  const enroll = vi.fn().mockResolvedValue(fake.enrollResult);
  const challengeAndVerify = vi.fn().mockResolvedValue({ data: {}, error: fake.verifyError });
  const signInWithPassword = vi.fn().mockResolvedValue({ data: {}, error: fake.signInError });
  const signOut = vi.fn().mockResolvedValue({ error: fake.signOutError });
  const auth = {
    signInWithPassword,
    signOut,
    getUser: vi.fn().mockResolvedValue({ data: { user: fake.user }, error: fake.userError }),
    getSession: vi.fn().mockResolvedValue({ data: { session: fake.session }, error: null }),
    mfa: {
      enroll,
      unenroll,
      challengeAndVerify,
      listFactors: vi.fn().mockResolvedValue({ data: { all: fake.factors }, error: null }),
      getAuthenticatorAssuranceLevel: vi
        .fn()
        .mockResolvedValue({ data: fake.levels, error: fake.levelError }),
    },
  };
  const port = createSupabaseAuthPort(auth, {
    totpIssuer: TOTP_ISSUER,
  });
  return { port, auth, enroll, unenroll, challengeAndVerify, signInWithPassword, signOut };
}

describe("signInWithPassword", () => {
  it("should pass the credentials through and succeed", async () => {
    const { port, signInWithPassword } = createFakeAuth();
    const credentials = { email: "staff@example.org", password: "a-password" };

    await expect(port.signInWithPassword(credentials)).resolves.toEqual({
      ok: true,
      data: undefined,
    });
    expect(signInWithPassword).toHaveBeenCalledWith(credentials);
  });

  it("should map a rejection to invalid credentials and keep the detail for logs", async () => {
    const { port } = createFakeAuth({ signInError: FAILURE });

    const result = await port.signInWithPassword({ email: "a@b.c", password: "x" });

    expect(result).toMatchObject({ ok: false, code: "invalid_credentials" });
    expect(result.ok ? "" : result.detail).toContain("some_code");
  });

  it("should describe a failure without a code", async () => {
    const { port } = createFakeAuth({ signInError: { ...FAILURE, code: undefined } });

    const result = await port.signInWithPassword({ email: "a@b.c", password: "x" });

    expect(result.ok ? "" : result.detail).toBe("AuthApiError: rejected");
  });
});

describe("getState", () => {
  it("should report a signed in user with the level and the verified factor", async () => {
    const { port } = createFakeAuth({
      user: {
        id: "user-1",
        email: "staff@example.org",
        factors: [
          { id: "old", factor_type: "totp", status: "unverified", created_at: "2026-01-01" },
          { id: "older", factor_type: "totp", status: "verified", created_at: "2026-02-01" },
          { id: FACTOR_ID, factor_type: "totp", status: "verified", created_at: "2026-03-01" },
        ],
      },
      levels: { currentLevel: "aal1", nextLevel: "aal2" },
    });

    await expect(port.getState()).resolves.toEqual({
      status: "signed_in",
      userId: "user-1",
      email: "staff@example.org",
      currentLevel: "aal1",
      nextLevel: "aal2",
      verifiedFactorId: FACTOR_ID,
      accessToken: ACCESS_TOKEN,
    });
  });

  it("should default a missing level to aal1 and a missing email to empty", async () => {
    const { port } = createFakeAuth({
      user: { id: "user-2" },
      levels: { currentLevel: null, nextLevel: null },
    });

    await expect(port.getState()).resolves.toMatchObject({
      email: "",
      currentLevel: "aal1",
      nextLevel: "aal1",
      verifiedFactorId: null,
    });
  });

  it.each([
    ["the provider rejects the session", { userError: FAILURE }],
    ["the level cannot be read", { levelError: FAILURE }],
    ["the session has no token", { session: null }],
  ])("should report signed out when %s", async (_reason, overrides) => {
    const { port } = createFakeAuth(overrides);

    await expect(port.getState()).resolves.toEqual({ status: "signed_out" });
  });
});

describe("startTotpEnrolment", () => {
  it("should discard unfinished factors before enrolling a new one", async () => {
    const { port, enroll, unenroll } = createFakeAuth({
      factors: [
        { id: "stale", factor_type: "totp", status: "unverified" },
        { id: "keep", factor_type: "totp", status: "verified" },
      ],
    });

    const result = await port.startTotpEnrolment();

    expect(unenroll).toHaveBeenCalledTimes(1);
    expect(unenroll).toHaveBeenCalledWith({ factorId: "stale" });
    expect(enroll).toHaveBeenCalledWith({ factorType: "totp", issuer: TOTP_ISSUER });
    expect(result).toEqual({
      ok: true,
      data: {
        factorId: FACTOR_ID,
        qrCodeDataUri: "data:image/svg+xml;utf-8,<svg/>",
        secret: "SECRET",
      },
    });
  });

  it("should keep a QR code that already is a data URI", async () => {
    const { port } = createFakeAuth({
      enrollResult: {
        data: { id: FACTOR_ID, totp: { qr_code: "data:image/svg+xml;utf-8,<svg/>", secret: "S" } },
        error: null,
      },
    });

    const result = await port.startTotpEnrolment();

    expect(result.ok && result.data.qrCodeDataUri).toBe("data:image/svg+xml;utf-8,<svg/>");
  });

  it("should report a failed enrolment", async () => {
    const { port } = createFakeAuth({ enrollResult: { data: null, error: FAILURE } });

    await expect(port.startTotpEnrolment()).resolves.toMatchObject({
      ok: false,
      code: "unavailable",
    });
  });
});

describe("listUnverifiedTotpFactorIds", () => {
  it("should list only unfinished authenticator apps", async () => {
    const { port } = createFakeAuth({
      factors: [
        { id: "u1", factor_type: "totp", status: "unverified" },
        { id: "v1", factor_type: "totp", status: "verified" },
        { id: "p1", factor_type: "phone", status: "unverified" },
      ],
    });

    await expect(port.listUnverifiedTotpFactorIds()).resolves.toEqual({ ok: true, data: ["u1"] });
  });

  it("should report a failed lookup", async () => {
    const { port, auth } = createFakeAuth();
    auth.mfa.listFactors.mockResolvedValue({ data: null, error: FAILURE });

    await expect(port.listUnverifiedTotpFactorIds()).resolves.toMatchObject({ ok: false });
  });
});

describe("verifyTotp", () => {
  it("should succeed for a correct code", async () => {
    const { port, challengeAndVerify } = createFakeAuth();

    await expect(port.verifyTotp({ factorId: FACTOR_ID, code: "123456" })).resolves.toEqual({
      ok: true,
      data: undefined,
    });
    expect(challengeAndVerify).toHaveBeenCalledWith({
      factorId: FACTOR_ID,
      code: "123456",
    });
  });

  it("should report a wrong code as an invalid code", async () => {
    const { port } = createFakeAuth({ verifyError: FAILURE });

    await expect(port.verifyTotp({ factorId: FACTOR_ID, code: "000000" })).resolves.toMatchObject({
      ok: false,
      code: "invalid_code",
    });
  });
});

describe("signOut", () => {
  it("should end only this session", async () => {
    const { port, signOut } = createFakeAuth();

    await expect(port.signOut()).resolves.toEqual({ ok: true, data: undefined });
    expect(signOut).toHaveBeenCalledWith({ scope: "local" });
  });

  it("should report a failed sign out", async () => {
    const { port } = createFakeAuth({ signOutError: FAILURE });

    await expect(port.signOut()).resolves.toMatchObject({ ok: false, code: "unavailable" });
  });
});
