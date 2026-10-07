import { describe, expect, it } from "vitest";

import { withMinimumFailureDuration, type DurationClock } from "./min-duration";

function createFakeClock(stepMs: number) {
  const state = { nowMs: 0, slept: [] as number[] };
  const clock: DurationClock = {
    now: () => state.nowMs,
    sleep: (milliseconds) => {
      state.slept.push(milliseconds);
      state.nowMs += milliseconds;
      return Promise.resolve();
    },
  };
  const operation =
    <TResult extends { readonly ok: boolean }>(result: TResult) =>
    () => {
      state.nowMs += stepMs;
      return Promise.resolve(result);
    };
  return { state, clock, operation };
}

describe("withMinimumFailureDuration (QA)", () => {
  it("should pad a failure so every failure takes the same total time", async () => {
    const fast = createFakeClock(10);
    const slow = createFakeClock(700);

    await withMinimumFailureDuration(fast.operation({ ok: false }), {
      minimumMs: 1000,
      clock: fast.clock,
    });
    await withMinimumFailureDuration(slow.operation({ ok: false }), {
      minimumMs: 1000,
      clock: slow.clock,
    });

    expect(fast.state.nowMs).toBe(1000);
    expect(slow.state.nowMs).toBe(1000);
  });

  it("should not wait for a success", async () => {
    const fake = createFakeClock(5);

    await withMinimumFailureDuration(fake.operation({ ok: true }), {
      minimumMs: 1000,
      clock: fake.clock,
    });

    expect(fake.state.slept).toEqual([]);
  });

  it("should not wait when the failure already took exactly the minimum", async () => {
    const fake = createFakeClock(1000);

    await withMinimumFailureDuration(fake.operation({ ok: false }), {
      minimumMs: 1000,
      clock: fake.clock,
    });

    expect(fake.state.slept).toEqual([]);
  });

  it("should not wait when the failure took longer than the minimum", async () => {
    const fake = createFakeClock(2500);

    await withMinimumFailureDuration(fake.operation({ ok: false }), {
      minimumMs: 1000,
      clock: fake.clock,
    });

    expect(fake.state.slept).toEqual([]);
  });

  it("should return the very same result object", async () => {
    const fake = createFakeClock(1);
    const failure = { ok: false, reason: "x" } as const;

    const result = await withMinimumFailureDuration(fake.operation(failure), {
      minimumMs: 10,
      clock: fake.clock,
    });

    expect(result).toBe(failure);
  });

  it("should pass a thrown error through without sleeping", async () => {
    const fake = createFakeClock(1);

    await expect(
      withMinimumFailureDuration(() => Promise.reject(new Error("boom")), {
        minimumMs: 1000,
        clock: fake.clock,
      }),
    ).rejects.toThrow("boom");
    expect(fake.state.slept).toEqual([]);
  });
});
