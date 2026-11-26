import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import type { OverviewData } from "@core/types/overview.types";

import { OverviewCards } from "./overview-cards";

const ATTENDANCE_HEADING = { level: 2, name: "Last Sunday's attendance" } as const;
const VISITORS_HEADING = { level: 2, name: "New visitors this month" } as const;
const NO_CARDS_NOTE = "No figures are shown for your roles yet.";

describe("OverviewCards", () => {
  it("should show both cards as list items when the role may see both", () => {
    const overview: OverviewData = {
      lastSundayAttendance: { ok: true, data: null },
      newVisitorsThisMonth: { ok: true, data: 4 },
    };
    render(<OverviewCards overview={overview} />);

    expect(screen.getByRole("heading", ATTENDANCE_HEADING)).toBeInTheDocument();
    expect(screen.getByRole("heading", VISITORS_HEADING)).toBeInTheDocument();
    expect(screen.getAllByRole("listitem")).toHaveLength(2);
    expect(screen.queryByText(NO_CARDS_NOTE)).not.toBeInTheDocument();
  });

  it("should show only the attendance card for a role that may not see visitors", () => {
    render(
      <OverviewCards
        overview={{ lastSundayAttendance: { ok: true, data: null }, newVisitorsThisMonth: null }}
      />,
    );

    expect(screen.getByRole("heading", ATTENDANCE_HEADING)).toBeInTheDocument();
    expect(screen.queryByRole("heading", VISITORS_HEADING)).not.toBeInTheDocument();
    expect(screen.queryByText(NO_CARDS_NOTE)).not.toBeInTheDocument();
  });

  it("should show only the visitors card for a role that may not see attendance", () => {
    render(
      <OverviewCards
        overview={{ lastSundayAttendance: null, newVisitorsThisMonth: { ok: true, data: 0 } }}
      />,
    );

    expect(screen.getByRole("heading", VISITORS_HEADING)).toBeInTheDocument();
    expect(screen.queryByRole("heading", ATTENDANCE_HEADING)).not.toBeInTheDocument();
    expect(screen.queryByText(NO_CARDS_NOTE)).not.toBeInTheDocument();
  });

  it("should show a plain note and no card when the role may see no figures", () => {
    render(<OverviewCards overview={{ lastSundayAttendance: null, newVisitorsThisMonth: null }} />);

    expect(screen.getByText(NO_CARDS_NOTE)).toBeInTheDocument();
    expect(screen.queryByRole("heading", { level: 2 })).not.toBeInTheDocument();
  });
});
