import { describe, expect, it } from "vitest";

import { formatServiceDateTime } from "./date.utils";

describe("formatServiceDateTime", () => {
  it("should show the weekday, date and time of a Sunday service in church time", () => {
    const formatted = formatServiceDateTime("2026-10-25T08:00:00Z");

    expect(formatted).toContain("Sunday");
    expect(formatted).toContain("25 October 2026");
    expect(formatted).toContain("08:00");
  });

  it("should format a timestamp that carries a UTC offset", () => {
    expect(formatServiceDateTime("2026-10-25T08:00:00+00:00")).toContain("25 October 2026");
  });
});
