import { ERROR_MESSAGES } from "@core/errors/error-messages.data";

export const APP_ERROR_CODES = [
  "network",
  "unauthenticated",
  "forbidden",
  "validation",
  "not_found",
  "server",
  "invalid_credentials",
  "invalid_code",
  "rate_limited",
  "session_expired",
] as const;

export type AppErrorCode = (typeof APP_ERROR_CODES)[number];

/** What a screen may show. The technical detail stays on the server, in the logs. */
export type AppErrorView = {
  readonly code: AppErrorCode;
  readonly message: string;
};

export type AppError = AppErrorView & {
  readonly technicalDetail: string;
};

export function createAppError(code: AppErrorCode, technicalDetail: string): AppError {
  return { code, message: ERROR_MESSAGES[code], technicalDetail };
}

export function toErrorView({ code, message }: AppError): AppErrorView {
  return { code, message };
}

export type ActionResult<TData = undefined> =
  | { readonly ok: true; readonly data: TData }
  | { readonly ok: false; readonly error: AppErrorView };

export type Result<TData> =
  { readonly ok: true; readonly data: TData } | { readonly ok: false; readonly error: AppError };
