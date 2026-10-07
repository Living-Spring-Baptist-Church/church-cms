import { IDLE_TIMEOUT_MS } from "@core/data/auth.data";

const DECIMAL_RADIX = 10;
// A timestamp from the future (beyond normal clock drift) cannot come from this server, so it is distrusted.
const MAX_CLOCK_SKEW_MS = 60_000;
const DIGITS_ONLY_PATTERN = /^\d+$/;

export function parseActivityTimestamp(rawValue: string | undefined): number | null {
  if (rawValue === undefined || !DIGITS_ONLY_PATTERN.test(rawValue)) {
    return null;
  }
  return Number.parseInt(rawValue, DECIMAL_RADIX);
}

export type IdleCheck = {
  readonly lastActivityMs: number | null;
  readonly nowMs: number;
  readonly timeoutMs?: number;
};

/** A missing or unreadable timestamp counts as expired, so a deleted cookie never extends a session. */
export function isIdleExpired({
  lastActivityMs,
  nowMs,
  timeoutMs = IDLE_TIMEOUT_MS,
}: IdleCheck): boolean {
  if (lastActivityMs === null) {
    return true;
  }
  if (lastActivityMs > nowMs + MAX_CLOCK_SKEW_MS) {
    return true;
  }
  return nowMs - lastActivityMs >= timeoutMs;
}
