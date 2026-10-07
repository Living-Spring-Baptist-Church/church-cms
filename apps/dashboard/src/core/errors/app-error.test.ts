import { describe, expect, it } from "vitest";

import { APP_ERROR_CODES, createAppError, toErrorView } from "./app-error";
import { ERROR_MESSAGES } from "./error-messages.data";

describe("app errors", () => {
  it("should have a plain message for every code and never mention a backend", () => {
    APP_ERROR_CODES.forEach((code) => {
      expect(ERROR_MESSAGES[code].length).toBeGreaterThan(0);
      expect(ERROR_MESSAGES[code]).not.toMatch(/supabase|postgres|sql|exception/i);
    });
  });

  it("should use the exact non-revealing sign in message", () => {
    expect(ERROR_MESSAGES.invalid_credentials).toBe("Email or password is incorrect.");
  });

  it("should keep the technical detail off the view shown to users", () => {
    const error = createAppError("server", "stack trace here");

    expect(error.technicalDetail).toBe("stack trace here");
    expect(toErrorView(error)).toEqual({ code: "server", message: ERROR_MESSAGES.server });
  });
});
