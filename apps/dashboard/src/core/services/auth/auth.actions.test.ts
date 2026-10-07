import { beforeEach, describe, expect, it, vi } from "vitest";

import { IDLE_TIMEOUT_MS } from "@core/data/auth.data";
import { createAppError } from "@core/errors/app-error";

import {
  confirmEnrolmentAction,
  logoutAction,
  signInAction,
  startEnrolmentAction,
  verifyLoginCodeAction,
} from "./auth.actions";

const mocks = vi.hoisted(() => ({
  loginService: {
    signIn: vi.fn(),
    verifyLoginCode: vi.fn(),
    startEnrolment: vi.fn(),
    confirmEnrolment: vi.fn(),
    logout: vi.fn(),
  },
  readLastActivity: vi.fn(),
  touchActivity: vi.fn(),
  clearActivity: vi.fn(),
  warn: vi.fn(),
  withMinimumFailureDuration: vi.fn((operation: () => Promise<unknown>) => operation()),
}));

vi.mock("@core/auth/min-duration", () => ({
  withMinimumFailureDuration: mocks.withMinimumFailureDuration,
}));

vi.mock("@core/auth/request-context", () => ({
  createRequestLoginService: () => Promise.resolve(mocks.loginService),
  readLastActivity: mocks.readLastActivity,
  touchActivity: mocks.touchActivity,
  clearActivity: mocks.clearActivity,
  readRequestId: () => Promise.resolve("request-1"),
}));
vi.mock("next/navigation", () => ({
  redirect: (destination: string) => {
    throw new Error(`REDIRECT ${destination}`);
  },
}));
vi.mock("@config/logger", () => ({ logger: { warn: mocks.warn } }));

const VALID_LOGIN = { email: "staff@example.org", password: "a-password" };
const FRESH_ACTIVITY = Date.now();

beforeEach(() => {
  vi.clearAllMocks();
  mocks.readLastActivity.mockResolvedValue(FRESH_ACTIVITY);
  mocks.loginService.logout.mockResolvedValue({ ok: true, data: undefined });
});

describe("signInAction", () => {
  it("should reject malformed input without calling the service", async () => {
    const result = await signInAction({ email: "nope", password: "" });

    expect(result).toMatchObject({ ok: false, error: { code: "validation" } });
    expect(mocks.loginService.signIn).not.toHaveBeenCalled();
  });

  it("should go to the dashboard after a finished login and record the activity", async () => {
    mocks.loginService.signIn.mockResolvedValue({ ok: true, data: "complete" });

    await expect(signInAction(VALID_LOGIN)).rejects.toThrow("REDIRECT /");
    expect(mocks.touchActivity).toHaveBeenCalledTimes(1);
  });

  it("should apply the minimum failure duration to the password step", async () => {
    mocks.loginService.signIn.mockResolvedValue({
      ok: false,
      error: createAppError("invalid_credentials", "x"),
    });

    await signInAction(VALID_LOGIN);

    expect(mocks.withMinimumFailureDuration).toHaveBeenCalledWith(expect.any(Function), {
      minimumMs: 1000,
    });
  });

  it.each(["verify_code", "enrol"] as const)(
    "should return to the login page for %s",
    async (step) => {
      mocks.loginService.signIn.mockResolvedValue({ ok: true, data: step });

      await expect(signInAction(VALID_LOGIN)).rejects.toThrow("REDIRECT /login");
    },
  );

  it("should return the plain message and log the technical detail on failure", async () => {
    mocks.loginService.signIn.mockResolvedValue({
      ok: false,
      error: createAppError("invalid_credentials", "AuthApiError: bad"),
    });

    const result = await signInAction(VALID_LOGIN);

    expect(result).toEqual({
      ok: false,
      error: { code: "invalid_credentials", message: "Email or password is incorrect." },
    });
    expect(mocks.warn).toHaveBeenCalledWith(
      "Sign in failed",
      expect.objectContaining({ detail: "AuthApiError: bad", requestId: "request-1" }),
    );
    expect(JSON.stringify(mocks.warn.mock.calls)).not.toContain(VALID_LOGIN.password);
    expect(mocks.touchActivity).not.toHaveBeenCalled();
  });
});

describe("verifyLoginCodeAction", () => {
  it("should accept a code with spaces and finish the login", async () => {
    mocks.loginService.verifyLoginCode.mockResolvedValue({ ok: true, data: "complete" });

    await expect(verifyLoginCodeAction({ code: "123 456" })).rejects.toThrow("REDIRECT /");
    expect(mocks.loginService.verifyLoginCode).toHaveBeenCalledWith("123456");
  });

  it("should reject a code of the wrong length", async () => {
    await expect(verifyLoginCodeAction({ code: "12" })).resolves.toMatchObject({ ok: false });
    expect(mocks.loginService.verifyLoginCode).not.toHaveBeenCalled();
  });

  it("should sign out and report an expired session when idle for 30 minutes", async () => {
    mocks.readLastActivity.mockResolvedValue(Date.now() - IDLE_TIMEOUT_MS - 1);

    const result = await verifyLoginCodeAction({ code: "123456" });

    expect(result).toMatchObject({ ok: false, error: { code: "session_expired" } });
    expect(mocks.loginService.logout).toHaveBeenCalledTimes(1);
    expect(mocks.clearActivity).toHaveBeenCalledTimes(1);
    expect(mocks.loginService.verifyLoginCode).not.toHaveBeenCalled();
  });

  it("should treat a missing activity cookie as idle", async () => {
    mocks.readLastActivity.mockResolvedValue(null);

    await expect(verifyLoginCodeAction({ code: "123456" })).resolves.toMatchObject({
      error: { code: "session_expired" },
    });
  });

  it("should show the friendly message for a wrong code", async () => {
    mocks.loginService.verifyLoginCode.mockResolvedValue({
      ok: false,
      error: createAppError("invalid_code", "bad code"),
    });

    await expect(verifyLoginCodeAction({ code: "000000" })).resolves.toMatchObject({
      error: { message: "That code is not correct. Try again." },
    });
  });
});

describe("startEnrolmentAction", () => {
  it("should return the QR code and secret for the person enrolling", async () => {
    const enrolment = { factorId: "f1", qrCodeDataUri: "data:", secret: "S" };
    mocks.loginService.startEnrolment.mockResolvedValue({ ok: true, data: enrolment });

    await expect(startEnrolmentAction()).resolves.toEqual({ ok: true, data: enrolment });
  });

  it("should return the error when enrolment cannot start", async () => {
    mocks.loginService.startEnrolment.mockResolvedValue({
      ok: false,
      error: createAppError("server", "x"),
    });

    await expect(startEnrolmentAction()).resolves.toMatchObject({ ok: false });
  });

  it("should refuse when the session idled out", async () => {
    mocks.readLastActivity.mockResolvedValue(null);

    await expect(startEnrolmentAction()).resolves.toMatchObject({
      error: { code: "session_expired" },
    });
    expect(mocks.loginService.startEnrolment).not.toHaveBeenCalled();
  });
});

describe("confirmEnrolmentAction", () => {
  it("should finish and go to the dashboard", async () => {
    mocks.loginService.confirmEnrolment.mockResolvedValue({ ok: true, data: "complete" });

    await expect(confirmEnrolmentAction({ factorId: "f1", code: "123456" })).rejects.toThrow(
      "REDIRECT /",
    );
    expect(mocks.loginService.confirmEnrolment).toHaveBeenCalledWith({
      factorId: "f1",
      code: "123456",
    });
  });

  it("should reject invalid input and an idle session", async () => {
    await expect(confirmEnrolmentAction({ factorId: "", code: "123456" })).resolves.toMatchObject({
      ok: false,
    });
    mocks.readLastActivity.mockResolvedValue(null);
    await expect(confirmEnrolmentAction({ factorId: "f1", code: "123456" })).resolves.toMatchObject(
      {
        error: { code: "session_expired" },
      },
    );
  });
});

describe("logoutAction", () => {
  it("should end the session, clear the activity cookie and go to the login page", async () => {
    await expect(logoutAction()).rejects.toThrow("REDIRECT /login");

    expect(mocks.loginService.logout).toHaveBeenCalledTimes(1);
    expect(mocks.clearActivity).toHaveBeenCalledTimes(1);
  });

  it("should still clear the activity cookie and log when sign out fails", async () => {
    mocks.loginService.logout.mockResolvedValue({
      ok: false,
      error: createAppError("server", "down"),
    });

    await expect(logoutAction()).rejects.toThrow("REDIRECT /login");
    expect(mocks.warn).toHaveBeenCalledWith("Sign out failed", expect.anything());
    expect(mocks.clearActivity).toHaveBeenCalledTimes(1);
  });
});
