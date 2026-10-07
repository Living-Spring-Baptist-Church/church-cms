export type DurationClock = {
  readonly now: () => number;
  readonly sleep: (milliseconds: number) => Promise<void>;
};

export const SYSTEM_CLOCK: DurationClock = {
  now: () => Date.now(),
  sleep: (milliseconds) =>
    new Promise((resolve) => {
      setTimeout(resolve, milliseconds);
    }),
};

export type MinimumDurationOptions = {
  readonly minimumMs: number;
  readonly clock?: DurationClock;
};

/** Runs the operation and, when it failed, waits until at least `minimumMs` have passed since the start. */
export async function withMinimumFailureDuration<TResult extends { readonly ok: boolean }>(
  operation: () => Promise<TResult>,
  { minimumMs, clock = SYSTEM_CLOCK }: MinimumDurationOptions,
): Promise<TResult> {
  const startedAt = clock.now();
  const result = await operation();
  const remaining = minimumMs - (clock.now() - startedAt);
  if (!result.ok && remaining > 0) {
    await clock.sleep(remaining);
  }
  return result;
}
