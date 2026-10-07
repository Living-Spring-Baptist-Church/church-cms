import { describe, expect, it } from "vitest";

import { AUTH_COPY } from "@core/copy/auth.copy";

import { enrolmentCodeSchema, loginSchema, totpCodeSchema } from "./auth.schema";

const VALID_PASSWORD = "Dev-Only-Passw0rd";

function loginMessages(input: { email: string; password: string }): string[] {
  const parsed = loginSchema.safeParse(input);
  return parsed.success ? [] : parsed.error.issues.map((issue) => issue.message);
}

describe("loginSchema (QA)", () => {
  it("should trim spaces around the email and keep its case for the provider to normalise", () => {
    const parsed = loginSchema.parse({ email: "  Pastor@Demo.Church  ", password: VALID_PASSWORD });

    expect(parsed.email).toBe("Pastor@Demo.Church");
  });

  it("should keep spaces inside and around a password", () => {
    const parsed = loginSchema.parse({ email: "a@demo.church", password: "  two words  " });

    expect(parsed.password).toBe("  two words  ");
  });

  it("should accept an email of exactly 254 characters and refuse 255", () => {
    const domain = "@demo.church";
    const localPartOf = (total: number) => "a".repeat(total - domain.length);
    const withinLimit = `${localPartOf(254)}${domain}`;

    expect(withinLimit).toHaveLength(254);
    expect(
      loginMessages({ email: `${"a".repeat(64)}@${"b".repeat(63)}.church`, password: "x" }),
    ).toEqual([]);
    expect(loginMessages({ email: `${localPartOf(255)}${domain}`, password: "x" })).toEqual([
      AUTH_COPY.login.emailInvalid,
    ]);
  });

  it("should accept a 72 character password and refuse 73", () => {
    expect(loginMessages({ email: "a@demo.church", password: "p".repeat(72) })).toEqual([]);
    expect(loginMessages({ email: "a@demo.church", password: "p".repeat(73) })).toEqual([
      AUTH_COPY.login.passwordRequired,
    ]);
  });

  it.each([
    "",
    " ",
    "not-an-email",
    "a@b",
    "@demo.church",
    "a@@demo.church",
    "a b@demo.church",
    "'; drop table staff; --@demo.church",
    "<script>alert(1)</script>@demo.church",
  ])("should refuse the email %j with the plain email message and nothing else", (email) => {
    expect(loginMessages({ email, password: VALID_PASSWORD })).toEqual([
      AUTH_COPY.login.emailInvalid,
    ]);
  });

  it("should never name an account, a role or an account state in any validation message", () => {
    const messages = [
      ...loginMessages({ email: "", password: "" }),
      ...loginMessages({ email: "x", password: "p".repeat(10_000) }),
    ].join(" ");

    expect(messages).not.toMatch(
      /exist|found|deactivat|inactive|disabled|unknown|register|account/i,
    );
  });
});

describe("one time code schemas (QA)", () => {
  it.each(["123456", "123 456", " 123456 ", "1 2 3 4 5 6", "123\t456", "123 456"])(
    "should accept %j as 123456",
    (code) => {
      expect(totpCodeSchema.parse({ code }).code).toBe("123456");
    },
  );

  it.each([
    "",
    "12345",
    "1234567",
    "12345a",
    "abcdef",
    "12-3456",
    "12.3456",
    "١٢٣٤٥٦",
    "１２３４５６",
    "123456​",
    "0x1234",
    "1e5000",
    "123456\n123456",
    "000 00",
  ])("should refuse %j with the plain code message", (code) => {
    const parsed = totpCodeSchema.safeParse({ code });

    expect(parsed.success).toBe(false);
    expect(parsed.error?.issues.map((issue) => issue.message)).toEqual([
      AUTH_COPY.verify.codeInvalid,
    ]);
  });

  it("should keep a leading zero code as text", () => {
    expect(totpCodeSchema.parse({ code: "000123" }).code).toBe("000123");
  });

  it("should require a factor id when confirming an enrolment", () => {
    expect(enrolmentCodeSchema.safeParse({ factorId: "", code: "123456" }).success).toBe(false);
    expect(enrolmentCodeSchema.safeParse({ code: "123456" }).success).toBe(false);
    expect(enrolmentCodeSchema.parse({ factorId: "f1", code: "123 456" })).toEqual({
      factorId: "f1",
      code: "123456",
    });
  });
});
