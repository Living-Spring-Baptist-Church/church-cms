const SECONDS_PER_MINUTE = 60;
const MILLISECONDS_PER_SECOND = 1000;

/** SET-04: staff are signed out after this many minutes without a request. */
export const IDLE_TIMEOUT_MINUTES = 30;
export const IDLE_TIMEOUT_MS = IDLE_TIMEOUT_MINUTES * SECONDS_PER_MINUTE * MILLISECONDS_PER_SECOND;

/** httpOnly cookie holding the epoch milliseconds of the last request. */
export const ACTIVITY_COOKIE_NAME = "lbc_last_activity";

/** Query parameter on the login page that explains why the visitor is there. */
export const LOGIN_REASON_PARAM = "reason";
export const LOGIN_REASON_IDLE = "idle";

export const TOTP_CODE_LENGTH = 6;

export const REQUEST_ID_HEADER = "x-request-id";
export const FORWARDED_PROTO_HEADER = "x-forwarded-proto";
export const ORIGIN_HEADER = "origin";

export const CACHE_CONTROL_HEADER = "Cache-Control";
/** Authenticated pages are private to one user and must never be stored by a cache. */
export const PRIVATE_CACHE_CONTROL = "private, no-store";

export const LOGIN_AUDIT_ACTION = "LOGIN";
export const LOGIN_AUDIT_TABLE = "staff";
export const LOGIN_METHOD_PASSWORD = "password";
export const LOGIN_METHOD_PASSWORD_AND_TOTP = "password+totp";

export type LoginMethod = typeof LOGIN_METHOD_PASSWORD | typeof LOGIN_METHOD_PASSWORD_AND_TOTP;

/**
 * Every failed password step takes at least this long, so a wrong password, an unknown email and a
 * deactivated account cannot be told apart by timing. Set above the slowest failure path.
 */
export const SIGN_IN_MIN_FAILURE_MS = 1000;
