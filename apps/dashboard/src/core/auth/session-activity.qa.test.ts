import { describe, expect, it } from "vitest";

import { IDLE_TIMEOUT_MS } from "@core/data/auth.data";

import { isIdleExpired, parseActivityTimestamp } from "./session-activity";

const NOW_MS = 1_790_000_000_000;
const ONE_SECOND_MS = 1000;
const CLOCK_SKEW_MS = 60_000;

describe("isIdleExpired boundaries (QA)", () => {
  it("should keep a session alive one millisecond before the limit", () => {
    expect(isIdleExpired({ lastActivityMs: NOW_MS - IDLE_TIMEOUT_MS + 1, nowMs: NOW_MS })).toBe(
      false,
    );
  });

  it("should end a session at exactly 30 minutes", () => {
    expect(isIdleExpired({ lastActivityMs: NOW_MS - IDLE_TIMEOUT_MS, nowMs: NOW_MS })).toBe(true);
  });

  it("should keep a session alive at 29 minutes and end it at 31 minutes", () => {
    const minuteMs = 60 * ONE_SECOND_MS;

    expect(isIdleExpired({ lastActivityMs: NOW_MS - 29 * minuteMs, nowMs: NOW_MS })).toBe(false);
    expect(isIdleExpired({ lastActivityMs: NOW_MS - 31 * minuteMs, nowMs: NOW_MS })).toBe(true);
  });

  it("should accept a timestamp up to one minute ahead and distrust anything further", () => {
    expect(isIdleExpired({ lastActivityMs: NOW_MS + CLOCK_SKEW_MS, nowMs: NOW_MS })).toBe(false);
    expect(isIdleExpired({ lastActivityMs: NOW_MS + CLOCK_SKEW_MS + 1, nowMs: NOW_MS })).toBe(true);
  });

  it("should treat a missing timestamp as expired", () => {
    expect(isIdleExpired({ lastActivityMs: null, nowMs: NOW_MS })).toBe(true);
  });

  it("should treat the epoch as expired", () => {
    expect(isIdleExpired({ lastActivityMs: 0, nowMs: NOW_MS })).toBe(true);
  });

  it("should honour a custom timeout", () => {
    expect(isIdleExpired({ lastActivityMs: NOW_MS - 5000, nowMs: NOW_MS, timeoutMs: 5000 })).toBe(
      true,
    );
    expect(isIdleExpired({ lastActivityMs: NOW_MS - 4999, nowMs: NOW_MS, timeoutMs: 5000 })).toBe(
      false,
    );
  });
});

describe("parseActivityTimestamp (QA)", () => {
  it.each(["", " 1", "1 ", "-1", "+1", "1.5", "1e3", "0x10", "abc", "1,000", "٣٤", "１２", "12\n"])(
    "should reject %j",
    (rawValue) => {
      expect(parseActivityTimestamp(rawValue)).toBeNull();
    },
  );

  it("should reject a missing cookie", () => {
    expect(parseActivityTimestamp(undefined)).toBeNull();
  });

  it("should read plain digits", () => {
    expect(parseActivityTimestamp("0")).toBe(0);
    expect(parseActivityTimestamp(String(NOW_MS))).toBe(NOW_MS);
  });

  it("should turn a huge digit string into a timestamp that counts as expired", () => {
    const parsed = parseActivityTimestamp("9".repeat(30));

    expect(isIdleExpired({ lastActivityMs: parsed, nowMs: NOW_MS })).toBe(true);
  });
});
