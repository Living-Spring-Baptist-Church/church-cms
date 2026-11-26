import { CHURCH_LOCALE, CHURCH_TIME_ZONE } from "@core/data/church.data";

/** Formats an ISO timestamp as, for example, "Sunday, 25 October 2026 at 09:00" in church time. */
export function formatServiceDateTime(isoTimestamp: string): string {
  return new Intl.DateTimeFormat(CHURCH_LOCALE, {
    weekday: "long",
    day: "numeric",
    month: "long",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    timeZone: CHURCH_TIME_ZONE,
  }).format(new Date(isoTimestamp));
}
