import { describe, expect, it } from "vitest";

import { FACTOR_ID, createProfile, createSession, setup } from "./login-test-fakes";

describe("second authenticator guard", () => {
  const withFactorAtAal1 = [createSession({ nextLevel: "aal2", verifiedFactorId: FACTOR_ID })];
  const withFactorAtAal2 = [
    createSession({ currentLevel: "aal2", nextLevel: "aal2", verifiedFactorId: FACTOR_ID }),
  ];

  it("should refuse to start an enrolment at aal1 when an app is already verified", async () => {
    const { service, auth } = setup({ states: withFactorAtAal1 });

    await expect(service.startEnrolment()).resolves.toMatchObject({
      ok: false,
      error: { code: "forbidden" },
    });
    expect(auth.startTotpEnrolment).not.toHaveBeenCalled();
  });

  it("should refuse to confirm an enrolment at aal1 when an app is already verified", async () => {
    const { service, auth, recordLogin } = setup({ states: withFactorAtAal1 });

    await expect(
      service.confirmEnrolment({ factorId: FACTOR_ID, code: "123456" }),
    ).resolves.toMatchObject({ ok: false, error: { code: "forbidden" } });
    expect(auth.verifyTotp).not.toHaveBeenCalled();
    expect(recordLogin).not.toHaveBeenCalled();
  });

  it("should not let the verified app be confirmed as if it were a new one", async () => {
    const { service, auth, recordLogin } = setup();
    auth.listUnverifiedTotpFactorIds.mockResolvedValue({ ok: true, data: ["other-factor"] });

    await expect(
      service.confirmEnrolment({ factorId: FACTOR_ID, code: "123456" }),
    ).resolves.toMatchObject({ ok: false, error: { code: "forbidden" } });
    expect(auth.verifyTotp).not.toHaveBeenCalled();
    expect(recordLogin).not.toHaveBeenCalled();
  });

  it("should report a failed lookup of pending apps", async () => {
    const { service, auth } = setup();
    auth.listUnverifiedTotpFactorIds.mockResolvedValue({
      ok: false,
      code: "unavailable",
      detail: "x",
    });

    await expect(
      service.confirmEnrolment({ factorId: FACTOR_ID, code: "123456" }),
    ).resolves.toMatchObject({ ok: false, error: { code: "server" } });
  });

  it("should allow adding another app from a session that already passed two-factor", async () => {
    const { service, auth, recordLogin } = setup({
      states: withFactorAtAal2,
      profile: { ok: true, data: createProfile(["pastor"]) },
    });

    await expect(service.startEnrolment()).resolves.toMatchObject({ ok: true });
    await expect(
      service.confirmEnrolment({ factorId: FACTOR_ID, code: "123456" }),
    ).resolves.toEqual({ ok: true, data: "complete" });
    expect(auth.verifyTotp).toHaveBeenCalledTimes(1);
    expect(recordLogin).not.toHaveBeenCalled();
  });

  it("should write exactly one LOGIN row when forced enrolment finishes a login", async () => {
    const { service, recordLogin } = setup({
      profile: { ok: true, data: createProfile(["pastor"]) },
    });

    await service.confirmEnrolment({ factorId: FACTOR_ID, code: "123456" });

    expect(recordLogin).toHaveBeenCalledTimes(1);
    expect(recordLogin).toHaveBeenCalledWith(expect.anything(), "password+totp");
  });

  it("should not log a second LOGIN when the code step is repeated at aal2", async () => {
    const { service, auth, recordLogin } = setup({ states: withFactorAtAal2 });

    await expect(service.verifyLoginCode("123456")).resolves.toMatchObject({
      ok: false,
      error: { code: "forbidden" },
    });
    expect(auth.verifyTotp).not.toHaveBeenCalled();
    expect(recordLogin).not.toHaveBeenCalled();
  });
});
