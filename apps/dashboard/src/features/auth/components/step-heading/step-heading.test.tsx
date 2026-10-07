import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { StepHeading } from "./step-heading";

describe("StepHeading", () => {
  it("should render the page heading", () => {
    render(<StepHeading heading="Enter your code" shouldTakeFocus={false} />);

    expect(screen.getByRole("heading", { level: 1, name: "Enter your code" })).toBeInTheDocument();
  });

  it("should take focus when a new step appears so it is announced", () => {
    render(<StepHeading heading="Enter your code" shouldTakeFocus />);

    expect(screen.getByRole("heading", { name: "Enter your code" })).toHaveFocus();
  });

  it("should leave focus alone on the first screen", () => {
    render(<StepHeading heading="Sign in" shouldTakeFocus={false} />);

    expect(screen.getByRole("heading", { name: "Sign in" })).not.toHaveFocus();
  });
});
