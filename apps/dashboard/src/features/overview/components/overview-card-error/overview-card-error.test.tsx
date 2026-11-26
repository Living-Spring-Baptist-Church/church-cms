import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { OverviewCardError } from "./overview-card-error";

describe("OverviewCardError", () => {
  it("should announce the message as an alert", () => {
    render(
      <OverviewCardError message="Something went wrong on our side. Try again in a moment." />,
    );

    expect(screen.getByRole("alert")).toHaveTextContent(
      "Something went wrong on our side. Try again in a moment.",
    );
  });

  it("should offer a retry link back to the overview", () => {
    render(<OverviewCardError message="Any message" />);

    expect(screen.getByRole("link", { name: "Try again" })).toHaveAttribute("href", "/");
  });
});
