import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { OverviewCard } from "./overview-card";

describe("OverviewCard", () => {
  it("should show the title as a level 2 heading", () => {
    render(<OverviewCard title="New visitors this month">body</OverviewCard>);

    expect(
      screen.getByRole("heading", { level: 2, name: "New visitors this month" }),
    ).toBeInTheDocument();
  });

  it("should render its children inside the card", () => {
    render(
      <OverviewCard title="Any title">
        <p>Card body text</p>
      </OverviewCard>,
    );

    expect(screen.getByText("Card body text")).toBeInTheDocument();
  });
});
