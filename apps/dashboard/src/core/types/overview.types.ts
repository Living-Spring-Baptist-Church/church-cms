import type { Result } from "@core/errors/app-error";

export type AttendanceHeadcount = {
  readonly men: number;
  readonly women: number;
  readonly children: number;
  readonly visitors: number;
};

/** The most recent Sunday service on or before now. `headcount` is null until counts are recorded. */
export type LastSundayAttendance = {
  readonly serviceName: string;
  readonly startsAt: string;
  readonly headcount: AttendanceHeadcount | null;
};

/**
 * One result per card the signed-in role may see. A null card was not read at all, because the
 * role has no permission for it, so its data never reaches the page.
 */
export type OverviewData = {
  readonly lastSundayAttendance: Result<LastSundayAttendance | null> | null;
  /** Number of people whose first visit falls in the current calendar month, church time. */
  readonly newVisitorsThisMonth: Result<number> | null;
};
