import { describe, expect, it, vi } from "vitest";

import { SYSTEM_CLOCK, withMinimumFailureDuration, type DurationClock } from "./min-duration";

function createFakeClock() {
  let nowMs = 0;
  const sleep = vi.fn((milliseconds: number) => {
    nowMs += milliseconds;
    return Promise.resolve();
  });
  const clock: DurationClock = { now: () => nowMs, sleep };
  return {
    clock,
    sleep,
    /** An operation that takes `durationMs` and then fails or succeeds. */
    operation: (durationMs: number, ok: boolean) => () => {
      nowMs += durationMs;
      return Promise.resolve({ ok });
    },
  };
}

describe("withMinimumFailureDuration", () => {
  it("should wait out the rest of the minimum after a fast failure", async () => {
    const { clock, sleep, operation } = createFakeClock();

    const result = await withMinimumFailureDuration(operation(100, false), {
      minimumMs: 1000,
      clock,
    });

    expect(result).toEqual({ ok: false });
    expect(sleep).toHaveBeenCalledWith(900);
  });

  it("should make fast and slow failures take the same time", async () => {
    const fast = createFakeClock();
    const slow = createFakeClock();

    await withMinimumFailureDuration(fast.operation(50, false), {
      minimumMs: 1000,
      clock: fast.clock,
    });
    await withMinimumFailureDuration(slow.operation(400, false), {
      minimumMs: 1000,
      clock: slow.clock,
    });

    expect(fast.clock.now()).toBe(1000);
    expect(slow.clock.now()).toBe(1000);
  });

  it("should not wait after a failure that already took longer than the minimum", async () => {
    const { clock, sleep, operation } = createFakeClock();

    await withMinimumFailureDuration(operation(1500, false), { minimumMs: 1000, clock });

    expect(sleep).not.toHaveBeenCalled();
  });

  it("should never delay a success", async () => {
    const { clock, sleep, operation } = createFakeClock();

    await expect(
      withMinimumFailureDuration(operation(10, true), { minimumMs: 1000, clock }),
    ).resolves.toEqual({ ok: true });
    expect(sleep).not.toHaveBeenCalled();
  });

  it("should sleep for real with the system clock", async () => {
    const before = SYSTEM_CLOCK.now();
    await SYSTEM_CLOCK.sleep(5);

    expect(SYSTEM_CLOCK.now() - before).toBeGreaterThanOrEqual(4);
  });
});
