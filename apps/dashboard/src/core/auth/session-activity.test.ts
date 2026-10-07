import { describe, expect, it } from "vitest";

import { IDLE_TIMEOUT_MS } from "@core/data/auth.data";

import { isIdleExpired, parseActivityTimestamp } from "./session-activity";

const NOW_MS = 1_800_000_000_000;

describe("parseActivityTimestamp", () => {
  it("should read epoch milliseconds", () => {
    expect(parseActivityTimestamp(String(NOW_MS))).toBe(NOW_MS);
  });

  it.each([undefined, "", "abc", "-5", "12.5", "1e9"])("should reject %s", (rawValue) => {
    expect(parseActivityTimestamp(rawValue)).toBeNull();
  });
});

describe("isIdleExpired", () => {
  it("should keep a session that was active a moment ago", () => {
    expect(isIdleExpired({ lastActivityMs: NOW_MS - 1, nowMs: NOW_MS })).toBe(false);
  });

  it("should keep a session just inside the 30 minute limit", () => {
    expect(isIdleExpired({ lastActivityMs: NOW_MS - IDLE_TIMEOUT_MS + 1, nowMs: NOW_MS })).toBe(
      false,
    );
  });

  it("should expire a session exactly at the limit", () => {
    expect(isIdleExpired({ lastActivityMs: NOW_MS - IDLE_TIMEOUT_MS, nowMs: NOW_MS })).toBe(true);
  });

  it("should expire a session with no recorded activity", () => {
    expect(isIdleExpired({ lastActivityMs: null, nowMs: NOW_MS })).toBe(true);
  });

  it("should honour a custom timeout", () => {
    expect(isIdleExpired({ lastActivityMs: NOW_MS - 10, nowMs: NOW_MS, timeoutMs: 5 })).toBe(true);
  });

  it("should tolerate a little clock drift but expire a timestamp from the future", () => {
    expect(isIdleExpired({ lastActivityMs: NOW_MS + 30_000, nowMs: NOW_MS })).toBe(false);
    expect(isIdleExpired({ lastActivityMs: NOW_MS + 61_000, nowMs: NOW_MS })).toBe(true);
  });

  it("should use 30 minutes", () => {
    expect(IDLE_TIMEOUT_MS).toBe(1_800_000);
  });
});
