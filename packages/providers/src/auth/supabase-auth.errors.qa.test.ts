import { describe, expect, it } from "vitest";

import {
  mapCodeError,
  mapGeneralError,
  mapSignInError,
  type VendorAuthError,
} from "./supabase-auth.errors";

function vendorError(overrides: Partial<VendorAuthError>): VendorAuthError {
  return { name: "AuthApiError", message: "raw vendor text", ...overrides };
}

describe("mapSignInError (QA)", () => {
  it.each([
    ["invalid_credentials", 400],
    ["user_not_found", 400],
    ["email_not_confirmed", 400],
    ["user_banned", 403],
    ["validation_failed", 422],
    ["signup_disabled", 422],
    ["email_provider_disabled", 422],
    ["unexpected_failure", 400],
    [undefined, 400],
  ])("should show %s (status %s) as wrong credentials", (code, status) => {
    expect(mapSignInError(vendorError({ code, status }))).toBe("invalid_credentials");
  });

  it("should recognise a rate limit by status and by code", () => {
    expect(mapSignInError(vendorError({ status: 429 }))).toBe("rate_limited");
    expect(mapSignInError(vendorError({ code: "over_request_rate_limit" }))).toBe("rate_limited");
  });

  it("should recognise an outage by status and by error name", () => {
    expect(mapSignInError(vendorError({ status: 500 }))).toBe("unavailable");
    expect(mapSignInError(vendorError({ status: 503 }))).toBe("unavailable");
    expect(mapSignInError(vendorError({ name: "AuthRetryableFetchError" }))).toBe("unavailable");
  });
});

describe("mapCodeError and mapGeneralError (QA)", () => {
  it("should treat a wrong or expired code as an invalid code", () => {
    expect(mapCodeError(vendorError({ code: "mfa_verification_failed", status: 400 }))).toBe(
      "invalid_code",
    );
    expect(mapCodeError(vendorError({ code: "mfa_challenge_expired", status: 400 }))).toBe(
      "invalid_code",
    );
  });

  it("should report a missing session at the code step as not signed in", () => {
    expect(mapCodeError(vendorError({ name: "AuthSessionMissingError" }))).toBe("not_signed_in");
    expect(mapGeneralError(vendorError({ name: "AuthSessionMissingError" }))).toBe("not_signed_in");
  });

  it("should never show a rate limited code attempt as a wrong code", () => {
    expect(mapCodeError(vendorError({ status: 429 }))).toBe("rate_limited");
  });

  it("should report an unknown general failure as unavailable, never as a credential problem", () => {
    expect(mapGeneralError(vendorError({ status: 400 }))).toBe("unavailable");
  });
});
