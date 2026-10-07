import type { AppErrorCode } from "@core/errors/app-error";

import { IDLE_TIMEOUT_MINUTES } from "@core/data/auth.data";

// The only text a user sees for a failure. Never backend wording, codes or stack traces.
export const ERROR_MESSAGES: Readonly<Record<AppErrorCode, string>> = {
  network: "We could not reach the server. Check your connection and try again.",
  unauthenticated: "Your session has ended. Sign in again to continue.",
  forbidden: "You do not have permission to do that.",
  validation: "Some of the details are not valid. Check them and try again.",
  not_found: "We could not find what you were looking for.",
  server: "Something went wrong on our side. Try again in a moment.",
  invalid_credentials: "Email or password is incorrect.",
  invalid_code: "That code is not correct. Try again.",
  rate_limited: "Too many attempts. Wait a few minutes and try again.",
  session_expired: `You were signed out after ${String(IDLE_TIMEOUT_MINUTES)} minutes without activity. Sign in again.`,
};
