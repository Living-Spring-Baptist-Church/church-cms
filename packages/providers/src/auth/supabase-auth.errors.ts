import type { AuthFailureCode } from "./auth.port";

export type VendorAuthError = {
  readonly name: string;
  readonly message: string;
  readonly status?: number | undefined;
  readonly code?: string | undefined;
};

const HTTP_TOO_MANY_REQUESTS = 429;
const HTTP_SERVER_ERROR_FLOOR = 500;
const RETRYABLE_FETCH_ERROR_NAME = "AuthRetryableFetchError";
const MISSING_SESSION_ERROR_NAME = "AuthSessionMissingError";
const RATE_LIMIT_CODE_PATTERN = /rate_limit/;

function isUnavailable(error: VendorAuthError): boolean {
  return (
    error.name === RETRYABLE_FETCH_ERROR_NAME ||
    (error.status !== undefined && error.status >= HTTP_SERVER_ERROR_FLOOR)
  );
}

function isRateLimited(error: VendorAuthError): boolean {
  return error.status === HTTP_TOO_MANY_REQUESTS || RATE_LIMIT_CODE_PATTERN.test(error.code ?? "");
}

/**
 * Every client error at sign in (wrong password, unknown email, unconfirmed or banned account)
 * becomes `invalid_credentials`, so a caller can never tell which one it was.
 */
export function mapSignInError(error: VendorAuthError): AuthFailureCode {
  if (isRateLimited(error)) {
    return "rate_limited";
  }
  return isUnavailable(error) ? "unavailable" : "invalid_credentials";
}

export function mapCodeError(error: VendorAuthError): AuthFailureCode {
  if (isRateLimited(error)) {
    return "rate_limited";
  }
  if (error.name === MISSING_SESSION_ERROR_NAME) {
    return "not_signed_in";
  }
  return isUnavailable(error) ? "unavailable" : "invalid_code";
}

export function mapGeneralError(error: VendorAuthError): AuthFailureCode {
  if (error.name === MISSING_SESSION_ERROR_NAME) {
    return "not_signed_in";
  }
  return isRateLimited(error) ? "rate_limited" : "unavailable";
}
