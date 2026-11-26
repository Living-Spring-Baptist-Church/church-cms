import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import type { OverviewData } from "@core/types/overview.types";

import { OverviewCards } from "./overview-cards";

describe("OverviewCards", () => {
  it("should show the attendance card when the role may see it", () => {
    const overview: OverviewData = { lastSundayAttendance: { ok: true, data: null } };
    render(<OverviewCards overview={overview} />);

    expect(
      screen.getByRole("heading", { level: 2, name: "Last Sunday's attendance" }),
    ).toBeInTheDocument();
  });

  it("should show a plain note and no card when the role may see no figures", () => {
    render(<OverviewCards overview={{ lastSundayAttendance: null }} />);

    expect(screen.getByText("No figures are shown for your roles yet.")).toBeInTheDocument();
    expect(screen.queryByRole("heading", { level: 2 })).not.toBeInTheDocument();
  });
});
