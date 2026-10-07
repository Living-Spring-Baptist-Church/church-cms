import { describe, expect, it } from "vitest";

import { mapCodeError, mapGeneralError, mapSignInError } from "./supabase-auth.errors";

const REJECTED = { name: "AuthApiError", message: "rejected", status: 400 };
const RATE_LIMITED = { name: "AuthApiError", message: "slow down", status: 429 };
const RATE_LIMITED_BY_CODE = {
  name: "AuthApiError",
  message: "slow down",
  code: "over_request_rate_limit",
};
const SERVER_DOWN = { name: "AuthApiError", message: "boom", status: 503 };
const NETWORK_DOWN = { name: "AuthRetryableFetchError", message: "fetch failed", status: 0 };
const NO_SESSION = { name: "AuthSessionMissingError", message: "no session", status: 400 };

describe("mapSignInError", () => {
  it("should hide the reason for every client error behind invalid credentials", () => {
    expect(mapSignInError(REJECTED)).toBe("invalid_credentials");
    expect(mapSignInError({ ...REJECTED, code: "email_not_confirmed" })).toBe(
      "invalid_credentials",
    );
    expect(mapSignInError({ ...REJECTED, code: "user_banned" })).toBe("invalid_credentials");
  });

  it("should report rate limiting by status or by code", () => {
    expect(mapSignInError(RATE_LIMITED)).toBe("rate_limited");
    expect(mapSignInError(RATE_LIMITED_BY_CODE)).toBe("rate_limited");
  });

  it("should report an unreachable or failing provider as unavailable", () => {
    expect(mapSignInError(SERVER_DOWN)).toBe("unavailable");
    expect(mapSignInError(NETWORK_DOWN)).toBe("unavailable");
  });
});

describe("mapCodeError", () => {
  it("should treat a rejected code as an invalid code", () => {
    expect(mapCodeError({ ...REJECTED, code: "mfa_verification_failed" })).toBe("invalid_code");
  });

  it("should separate rate limiting, a missing session and outages", () => {
    expect(mapCodeError(RATE_LIMITED)).toBe("rate_limited");
    expect(mapCodeError(NO_SESSION)).toBe("not_signed_in");
    expect(mapCodeError(SERVER_DOWN)).toBe("unavailable");
  });
});

describe("mapGeneralError", () => {
  it("should map a missing session, rate limiting and anything else", () => {
    expect(mapGeneralError(NO_SESSION)).toBe("not_signed_in");
    expect(mapGeneralError(RATE_LIMITED)).toBe("rate_limited");
    expect(mapGeneralError(REJECTED)).toBe("unavailable");
  });
});
