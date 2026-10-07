import { describe, expect, it } from "vitest";

import { APP_ERROR_CODES, createAppError, toErrorView } from "./app-error";
import { ERROR_MESSAGES } from "./error-messages.data";

const EM_DASH = String.fromCodePoint(0x2014);
const TECHNICAL_WORDS =
  /exception|stack|AuthApi|supabase|postgres|sql|PGRST|undefined|null|\d{3}\b(?!\s*minutes)/i;

describe("error messages (QA)", () => {
  it("should word the wrong credentials message exactly as the ticket asks", () => {
    expect(ERROR_MESSAGES.invalid_credentials).toBe("Email or password is incorrect.");
  });

  it("should word the wrong code message exactly", () => {
    expect(ERROR_MESSAGES.invalid_code).toBe("That code is not correct. Try again.");
  });

  it.each(APP_ERROR_CODES)("should give %s a plain sentence for users", (code) => {
    const message = ERROR_MESSAGES[code];

    expect(message).toMatch(/^[A-Z].*\.$/);
    expect(message).not.toContain(EM_DASH);
    expect(message).not.toMatch(TECHNICAL_WORDS);
  });

  it("should not reveal whether an email exists in any sign in message", () => {
    const signInMessages = [ERROR_MESSAGES.invalid_credentials, ERROR_MESSAGES.rate_limited];

    for (const message of signInMessages) {
      expect(message).not.toMatch(
        /no account|not found|does not exist|deactivat|unknown|inactive/i,
      );
    }
  });

  it("should keep technical detail out of the view a screen receives", () => {
    const view = toErrorView(createAppError("server", "AuthApiError: secret detail"));

    expect(JSON.stringify(view)).not.toContain("secret detail");
    expect(Object.keys(view).sort()).toEqual(["code", "message"]);
  });
});
