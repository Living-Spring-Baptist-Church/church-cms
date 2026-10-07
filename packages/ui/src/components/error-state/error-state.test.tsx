import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

import { ErrorState } from "./error-state";

describe("ErrorState", () => {
  it("should show the title and announce the message", () => {
    render(
      <ErrorState
        title="Something went wrong"
        message="Try again."
        retryLabel="Retry"
        onRetry={vi.fn()}
      />,
    );

    expect(
      screen.getByRole("heading", { level: 1, name: "Something went wrong" }),
    ).toBeInTheDocument();
    expect(screen.getByRole("alert")).toHaveTextContent("Try again.");
  });

  it("should call onRetry when the retry button is pressed", async () => {
    const handleRetry = vi.fn();
    render(<ErrorState title="Oops" message="Failed." retryLabel="Retry" onRetry={handleRetry} />);

    await userEvent.click(screen.getByRole("button", { name: "Retry" }));

    expect(handleRetry).toHaveBeenCalledTimes(1);
  });

  it("should render extra actions next to the retry button", () => {
    render(
      <ErrorState title="Oops" message="Failed." retryLabel="Retry" onRetry={vi.fn()}>
        <a href="/">Home</a>
      </ErrorState>,
    );

    expect(screen.getByRole("link", { name: "Home" })).toBeInTheDocument();
  });
});
