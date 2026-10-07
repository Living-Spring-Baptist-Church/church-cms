import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";

import { Label } from "./label";

describe("Label", () => {
  it("should name the control it points to", () => {
    render(
      <>
        <Label htmlFor="email">Email</Label>
        <input id="email" />
      </>,
    );

    expect(screen.getByRole("textbox", { name: "Email" })).toBeInTheDocument();
  });

  it("should focus its control when clicked", async () => {
    render(
      <>
        <Label htmlFor="email">Email</Label>
        <input id="email" />
      </>,
    );

    await userEvent.click(screen.getByText("Email"));

    expect(screen.getByRole("textbox")).toHaveFocus();
  });

  it("should merge a custom class name", () => {
    render(<Label className="mb-1">Name</Label>);

    expect(screen.getByText("Name")).toHaveClass("mb-1", "font-medium");
  });
});
