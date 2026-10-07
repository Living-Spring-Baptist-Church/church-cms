import { describe, expect, it } from "vitest";

import { enrolmentCodeSchema, loginSchema, totpCodeSchema } from "./auth.schema";

describe("loginSchema", () => {
  it("should accept an email and a password and trim the email", () => {
    const parsed = loginSchema.parse({ email: "  staff@example.org ", password: "secret" });

    expect(parsed).toEqual({ email: "staff@example.org", password: "secret" });
  });

  it.each(["", "not-an-email", "a@", "a".repeat(300) + "@example.org"])(
    "should reject the email %s",
    (email) => {
      expect(loginSchema.safeParse({ email, password: "secret" }).success).toBe(false);
    },
  );

  it("should reject an empty or oversized password", () => {
    expect(loginSchema.safeParse({ email: "a@example.org", password: "" }).success).toBe(false);
    expect(
      loginSchema.safeParse({ email: "a@example.org", password: "p".repeat(100) }).success,
    ).toBe(false);
  });

  it("should not enforce a password strength rule at sign in", () => {
    expect(loginSchema.safeParse({ email: "a@example.org", password: "x" }).success).toBe(true);
  });
});

describe("totpCodeSchema", () => {
  it("should accept six digits and remove spaces", () => {
    expect(totpCodeSchema.parse({ code: "123 456" })).toEqual({ code: "123456" });
    expect(totpCodeSchema.parse({ code: "000000" })).toEqual({ code: "000000" });
  });

  it.each(["", "12345", "1234567", "12a456", "１２３４５６"])("should reject %s", (code) => {
    expect(totpCodeSchema.safeParse({ code }).success).toBe(false);
  });
});

describe("enrolmentCodeSchema", () => {
  it("should need a factor id and a valid code", () => {
    expect(enrolmentCodeSchema.safeParse({ factorId: "f", code: "123456" }).success).toBe(true);
    expect(enrolmentCodeSchema.safeParse({ factorId: "", code: "123456" }).success).toBe(false);
    expect(enrolmentCodeSchema.safeParse({ factorId: "f", code: "1" }).success).toBe(false);
  });
});
