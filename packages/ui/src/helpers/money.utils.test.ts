import { describe, expect, it } from "vitest";

import { formatMoney } from "./money.utils";

describe("formatMoney", () => {
  it("should format zero with the currency symbol and two decimals", () => {
    expect(formatMoney(0, "GHS")).toBe("GH₵0.00");
  });

  it("should format a single pesewa", () => {
    expect(formatMoney(1, "GHS")).toBe("GH₵0.01");
  });

  it("should format a whole cedi amount", () => {
    expect(formatMoney(50000, "GHS")).toBe("GH₵500.00");
  });

  it("should format a large amount with thousands separators", () => {
    expect(formatMoney(123456789, "GHS")).toBe("GH₵1,234,567.89");
  });
});

describe("formatMoney negative amounts", () => {
  it("should format a negative amount such as a reversal", () => {
    expect(formatMoney(-250, "GHS")).toBe("-GH₵2.50");
  });
});

describe("formatMoney edge cases", () => {
  it("should format a very large amount exactly when it is below 2^52 pesewas", () => {
    expect(formatMoney(4503599627370497, "GHS")).toBe("GH₵45,035,996,273,704.97");
  });

  it("should format negative one pesewa", () => {
    expect(formatMoney(-1, "GHS")).toBe("-GH₵0.01");
  });

  it("should format another currency such as USD", () => {
    expect(formatMoney(12345, "USD")).toBe("US$123.45");
  });

  it("should throw a RangeError when the currency code is invalid", () => {
    expect(() => formatMoney(100, "NOPE1")).toThrow(RangeError);
  });

  it("should round a fractional minor amount to two decimals when given non-integer input", () => {
    expect(formatMoney(1.5, "GHS")).toBe("GH₵0.02");
  });

  it("should render NaN as text when given NaN", () => {
    expect(formatMoney(Number.NaN, "GHS")).toContain("NaN");
  });
});
