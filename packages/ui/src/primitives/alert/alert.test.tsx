import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { Alert } from "./alert";

describe("Alert", () => {
  it("should show its message with an icon and the given role", () => {
    const { container } = render(
      <Alert variant="destructive" role="alert">
        Email or password is incorrect.
      </Alert>,
    );

    expect(screen.getByRole("alert")).toHaveTextContent("Email or password is incorrect.");
    expect(container.querySelector("svg")).toHaveAttribute("aria-hidden", "true");
  });

  it.each([
    ["destructive", "text-destructive-text"],
    ["info", "bg-info-surface"],
    ["success", "bg-success-surface"],
  ] as const)("should style the %s variant", (variant, expectedClass) => {
    render(
      <Alert variant={variant} role="status">
        Message
      </Alert>,
    );

    expect(screen.getByRole("status")).toHaveClass(expectedClass);
  });

  it("should default to the info variant and merge a class name", () => {
    render(
      <Alert role="status" className="mt-4">
        Message
      </Alert>,
    );

    expect(screen.getByRole("status")).toHaveClass("bg-info-surface", "mt-4");
  });
});
