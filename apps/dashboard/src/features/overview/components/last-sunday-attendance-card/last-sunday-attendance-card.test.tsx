import { render, screen, within } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { createAppError } from "@core/errors/app-error";
import type { LastSundayAttendance } from "@core/types/overview.types";

import { LastSundayAttendanceCard } from "./last-sunday-attendance-card";

const RECORDED_SERVICE: LastSundayAttendance = {
  serviceName: "Sunday First Service",
  startsAt: "2026-10-25T08:00:00Z",
  headcount: { men: 40, women: 55, children: 18, visitors: 3 },
};

describe("LastSundayAttendanceCard", () => {
  it("should show the title as the card heading", () => {
    render(<LastSundayAttendanceCard result={{ ok: true, data: RECORDED_SERVICE }} />);

    expect(
      screen.getByRole("heading", { level: 2, name: "Last Sunday's attendance" }),
    ).toBeInTheDocument();
  });

  it("should show each headcount group with its number", () => {
    render(<LastSundayAttendanceCard result={{ ok: true, data: RECORDED_SERVICE }} />);

    const men = screen.getByText("Men").closest("div");
    const visitors = screen.getByText("Visitors").closest("div");
    expect(men).not.toBeNull();
    expect(within(men as HTMLElement).getByText("40")).toBeInTheDocument();
    expect(visitors).not.toBeNull();
    expect(within(visitors as HTMLElement).getByText("3")).toBeInTheDocument();
  });

  it("should show the service name and its date in church time", () => {
    render(<LastSundayAttendanceCard result={{ ok: true, data: RECORDED_SERVICE }} />);

    expect(screen.getByText("Sunday First Service")).toBeInTheDocument();
    expect(screen.getByText(/25 October 2026 at 08:00/)).toBeInTheDocument();
  });

  it("should show the empty state when no Sunday service has been recorded", () => {
    render(<LastSundayAttendanceCard result={{ ok: true, data: null }} />);

    expect(screen.getByText("No Sunday service has been recorded yet.")).toBeInTheDocument();
  });

  it("should show the service but say no counts exist when attendance was not recorded", () => {
    render(
      <LastSundayAttendanceCard
        result={{ ok: true, data: { ...RECORDED_SERVICE, headcount: null } }}
      />,
    );

    expect(screen.getByText(/Sunday First Service/)).toBeInTheDocument();
    expect(
      screen.getByText("Attendance has not been recorded for this service yet."),
    ).toBeInTheDocument();
  });

  it("should show the plain error message and a retry link when the read fails", () => {
    render(
      <LastSundayAttendanceCard
        result={{ ok: false, error: createAppError("network", "ECONNRESET on graphql") }}
      />,
    );

    expect(screen.getByRole("alert")).toHaveTextContent(
      "We could not reach the server. Check your connection and try again.",
    );
    expect(screen.getByRole("link", { name: "Try again" })).toHaveAttribute("href", "/");
    expect(screen.queryByText(/ECONNRESET/)).not.toBeInTheDocument();
  });
});
