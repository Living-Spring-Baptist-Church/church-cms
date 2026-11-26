import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { EmptyState } from "./empty-state";

describe("EmptyState", () => {
  it("should show the message as plain text", () => {
    render(<EmptyState message="No services have been recorded yet." />);

    expect(screen.getByText("No services have been recorded yet.")).toBeInTheDocument();
  });

  it("should render the next action when one is given", () => {
    render(
      <EmptyState message="No members yet.">
        <a href="/members/new">Add the first member</a>
      </EmptyState>,
    );

    expect(screen.getByRole("link", { name: "Add the first member" })).toBeInTheDocument();
  });

  it("should render without a next action", () => {
    render(<EmptyState message="Nothing to show." />);

    expect(screen.queryByRole("link")).not.toBeInTheDocument();
  });
});
