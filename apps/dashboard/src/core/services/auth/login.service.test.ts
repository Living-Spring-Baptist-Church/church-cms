import { describe, expect, it } from "vitest";

import { createAppError } from "@core/errors/app-error";

import {
  CREDENTIALS,
  FACTOR_ID,
  STAFF_ID,
  createProfile,
  createSession,
  setup,
} from "./login-test-fakes";

describe("signIn", () => {
  it("should complete and audit a password login for a role without two-factor", async () => {
    const { service, recordLogin } = setup();

    await expect(service.signIn(CREDENTIALS)).resolves.toEqual({ ok: true, data: "complete" });
    expect(recordLogin).toHaveBeenCalledWith(
      expect.objectContaining({ userId: STAFF_ID }),
      "password",
    );
  });

  it("should ask for a code when the user has an authenticator app, without auditing yet", async () => {
    const { service, recordLogin } = setup({
      states: [createSession({ nextLevel: "aal2", verifiedFactorId: FACTOR_ID })],
    });

    await expect(service.signIn(CREDENTIALS)).resolves.toEqual({ ok: true, data: "verify_code" });
    expect(recordLogin).not.toHaveBeenCalled();
  });

  it("should force enrolment for a role that requires two-factor and has no app", async () => {
    const { service, recordLogin } = setup({
      profile: { ok: true, data: createProfile(["pastor"]) },
    });

    await expect(service.signIn(CREDENTIALS)).resolves.toEqual({ ok: true, data: "enrol" });
    expect(recordLogin).not.toHaveBeenCalled();
  });

  it("should return the generic error for a wrong password", async () => {
    const { service, auth } = setup({
      signIn: { ok: false, code: "invalid_credentials", detail: "bad" },
    });

    const result = await service.signIn(CREDENTIALS);

    expect(result).toMatchObject({
      ok: false,
      error: { message: "Email or password is incorrect." },
    });
    expect(auth.signOut).not.toHaveBeenCalled();
  });

  it.each([
    ["has no staff row", { ok: true, data: null } as const],
    ["is deactivated", { ok: true, data: createProfile(["usher"], false) } as const],
  ])(
    "should sign out and use the same generic error when the account %s",
    async (_label, profile) => {
      const { service, auth, recordLogin } = setup({ profile });

      const result = await service.signIn(CREDENTIALS);

      expect(result).toMatchObject({ ok: false, error: { code: "invalid_credentials" } });
      expect(auth.signOut).toHaveBeenCalledTimes(1);
      expect(recordLogin).not.toHaveBeenCalled();
    },
  );

  it("should sign out and report a server problem when the profile cannot be read", async () => {
    const { service, auth } = setup({
      profile: { ok: false, error: createAppError("network", "down") },
    });

    await expect(service.signIn(CREDENTIALS)).resolves.toMatchObject({
      ok: false,
      error: { code: "network" },
    });
    expect(auth.signOut).toHaveBeenCalledTimes(1);
  });

  it.each([
    ["rate_limited", "rate_limited"],
    ["unavailable", "server"],
  ] as const)("should map the provider failure %s to %s", async (failure, expectedCode) => {
    const { service } = setup({ signIn: { ok: false, code: failure, detail: "x" } });

    await expect(service.signIn(CREDENTIALS)).resolves.toMatchObject({
      ok: false,
      error: { code: expectedCode },
    });
  });

  it("should fail when the session disappears right after sign in", async () => {
    const { service } = setup({ states: [{ status: "signed_out" }] });

    await expect(service.signIn(CREDENTIALS)).resolves.toMatchObject({
      ok: false,
      error: { code: "session_expired" },
    });
  });

  it("should refuse the login and sign out when it cannot be audited", async () => {
    const { service, auth } = setup({
      audit: { ok: false, error: createAppError("network", "down") },
    });

    await expect(service.signIn(CREDENTIALS)).resolves.toMatchObject({
      ok: false,
      error: { code: "network" },
    });
    expect(auth.signOut).toHaveBeenCalledTimes(1);
  });

  it("should treat a forbidden audit call as a refused login", async () => {
    const { service } = setup({
      audit: { ok: false, error: createAppError("forbidden", "AUTH_FORBIDDEN") },
    });

    await expect(service.signIn(CREDENTIALS)).resolves.toMatchObject({
      ok: false,
      error: { code: "invalid_credentials" },
    });
  });
});

describe("fail closed profiles", () => {
  it("should refuse a staff row with no role, with the generic error and a sign out", async () => {
    const { service, auth, recordLogin } = setup({
      profile: { ok: true, data: createProfile([]) },
    });

    await expect(service.signIn(CREDENTIALS)).resolves.toMatchObject({
      ok: false,
      error: { code: "invalid_credentials" },
    });
    expect(auth.signOut).toHaveBeenCalledTimes(1);
    expect(recordLogin).not.toHaveBeenCalled();
  });

  it("should force enrolment when the database holds a role the app does not know", async () => {
    const { service } = setup({
      profile: { ok: true, data: createProfile([], true, true) },
    });

    await expect(service.signIn(CREDENTIALS)).resolves.toEqual({ ok: true, data: "enrol" });
  });

  it("should show the password form for a role-less stale session", async () => {
    const { service } = setup({ profile: { ok: true, data: createProfile([]) } });

    await expect(service.loadLoginStep()).resolves.toEqual({ ok: true, data: "password" });
  });
});

describe("loadLoginStep", () => {
  it("should show the password form when nobody is signed in", async () => {
    const { service } = setup({ states: [{ status: "signed_out" }] });

    await expect(service.loadLoginStep()).resolves.toEqual({ ok: true, data: "password" });
  });

  it("should show the password form for a stale session of a deactivated account", async () => {
    const { service } = setup({ profile: { ok: true, data: null } });

    await expect(service.loadLoginStep()).resolves.toEqual({ ok: true, data: "password" });
  });

  it("should report the code step for a session at aal1 with an authenticator app", async () => {
    const { service } = setup({
      states: [createSession({ nextLevel: "aal2", verifiedFactorId: FACTOR_ID })],
    });

    await expect(service.loadLoginStep()).resolves.toEqual({ ok: true, data: "verify_code" });
  });

  it("should pass a profile read failure on", async () => {
    const { service } = setup({ profile: { ok: false, error: createAppError("server", "x") } });

    await expect(service.loadLoginStep()).resolves.toMatchObject({ ok: false });
  });
});

describe("verifyLoginCode", () => {
  const withFactor = [createSession({ nextLevel: "aal2", verifiedFactorId: FACTOR_ID })];

  it("should verify the code against the user's own factor and audit the login", async () => {
    const { service, auth, recordLogin } = setup({ states: withFactor });

    await expect(service.verifyLoginCode("123456")).resolves.toEqual({
      ok: true,
      data: "complete",
    });
    expect(auth.verifyTotp).toHaveBeenCalledWith({ factorId: FACTOR_ID, code: "123456" });
    expect(recordLogin).toHaveBeenCalledWith(expect.anything(), "password+totp");
  });

  it("should return the friendly error for a wrong code and not audit", async () => {
    const { service, recordLogin } = setup({
      states: withFactor,
      verify: { ok: false, code: "invalid_code", detail: "bad" },
    });

    await expect(service.verifyLoginCode("000000")).resolves.toMatchObject({
      ok: false,
      error: { message: "That code is not correct. Try again." },
    });
    expect(recordLogin).not.toHaveBeenCalled();
  });

  it("should require a session", async () => {
    const { service } = setup({ states: [{ status: "signed_out" }] });

    await expect(service.verifyLoginCode("123456")).resolves.toMatchObject({
      ok: false,
      error: { code: "session_expired" },
    });
  });

  it("should refuse a code when the user has no authenticator app", async () => {
    const { service, auth } = setup();

    await expect(service.verifyLoginCode("123456")).resolves.toMatchObject({ ok: false });
    expect(auth.verifyTotp).not.toHaveBeenCalled();
  });
});

describe("startEnrolment", () => {
  it("should start enrolment for an active signed in user", async () => {
    const { service } = setup();

    await expect(service.startEnrolment()).resolves.toMatchObject({
      ok: true,
      data: { factorId: FACTOR_ID },
    });
  });

  it("should not start for a visitor without a session", async () => {
    const { service, auth } = setup({ states: [{ status: "signed_out" }] });

    await expect(service.startEnrolment()).resolves.toMatchObject({ ok: false });
    expect(auth.startTotpEnrolment).not.toHaveBeenCalled();
  });

  it("should not start for a deactivated account", async () => {
    const { service, auth } = setup({
      profile: { ok: true, data: createProfile(["usher"], false) },
    });

    await expect(service.startEnrolment()).resolves.toMatchObject({ ok: false });
    expect(auth.startTotpEnrolment).not.toHaveBeenCalled();
  });

  it("should report a provider failure", async () => {
    const { service, auth } = setup();
    auth.startTotpEnrolment.mockResolvedValue({ ok: false, code: "unavailable", detail: "x" });

    await expect(service.startEnrolment()).resolves.toMatchObject({
      ok: false,
      error: { code: "server" },
    });
  });
});

describe("confirmEnrolment", () => {
  const confirmation = { factorId: FACTOR_ID, code: "123456" };

  it("should finish the login of a role that requires two-factor", async () => {
    const { service, recordLogin } = setup({
      profile: { ok: true, data: createProfile(["treasurer"]) },
    });

    await expect(service.confirmEnrolment(confirmation)).resolves.toEqual({
      ok: true,
      data: "complete",
    });
    expect(recordLogin).toHaveBeenCalledWith(expect.anything(), "password+totp");
  });

  it("should not audit a second login when optional enrolment happens inside a session", async () => {
    const { service, recordLogin } = setup();

    await expect(service.confirmEnrolment(confirmation)).resolves.toEqual({
      ok: true,
      data: "complete",
    });
    expect(recordLogin).not.toHaveBeenCalled();
  });

  it("should return the friendly error for a wrong code", async () => {
    const { service } = setup({ verify: { ok: false, code: "invalid_code", detail: "bad" } });

    await expect(service.confirmEnrolment(confirmation)).resolves.toMatchObject({
      ok: false,
      error: { code: "invalid_code" },
    });
  });

  it("should require a session and an active account", async () => {
    const signedOut = setup({ states: [{ status: "signed_out" }] });
    const deactivated = setup({ profile: { ok: true, data: null } });

    await expect(signedOut.service.confirmEnrolment(confirmation)).resolves.toMatchObject({
      ok: false,
    });
    await expect(deactivated.service.confirmEnrolment(confirmation)).resolves.toMatchObject({
      ok: false,
    });
    expect(deactivated.auth.verifyTotp).not.toHaveBeenCalled();
  });
});

describe("logout", () => {
  it("should end the session", async () => {
    const { service, auth } = setup();

    await expect(service.logout()).resolves.toEqual({ ok: true, data: undefined });
    expect(auth.signOut).toHaveBeenCalledTimes(1);
  });

  it("should report a failed sign out", async () => {
    const { service, auth } = setup();
    auth.signOut.mockResolvedValue({ ok: false, code: "unavailable", detail: "x" });

    await expect(service.logout()).resolves.toMatchObject({ ok: false });
  });
});
