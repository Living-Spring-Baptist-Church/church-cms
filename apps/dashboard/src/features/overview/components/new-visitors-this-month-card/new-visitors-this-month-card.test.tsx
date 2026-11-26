import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { createAppError } from "@core/errors/app-error";

import { NewVisitorsThisMonthCard } from "./new-visitors-this-month-card";

describe("NewVisitorsThisMonthCard", () => {
  it("should show the title as the card heading", () => {
    render(<NewVisitorsThisMonthCard result={{ ok: true, data: 7 }} />);

    expect(
      screen.getByRole("heading", { level: 2, name: "New visitors this month" }),
    ).toBeInTheDocument();
  });

  it("should show the number of new visitors with its label", () => {
    render(<NewVisitorsThisMonthCard result={{ ok: true, data: 7 }} />);

    expect(screen.getByRole("term")).toHaveTextContent("First visits since the start of the month");
    expect(screen.getByRole("definition")).toHaveTextContent("7");
  });

  it("should show a plain message instead of a zero when no one visited for the first time", () => {
    render(<NewVisitorsThisMonthCard result={{ ok: true, data: 0 }} />);

    expect(
      screen.getByText("No new visitors have been recorded this month yet."),
    ).toBeInTheDocument();
    expect(screen.queryByRole("definition")).not.toBeInTheDocument();
  });

  it("should show the plain error message and a retry link when the read fails", () => {
    render(
      <NewVisitorsThisMonthCard
        result={{ ok: false, error: createAppError("forbidden", "AUTH_FORBIDDEN from graphql") }}
      />,
    );

    expect(screen.getByRole("alert")).toHaveTextContent("You do not have permission to do that.");
    expect(screen.getByRole("link", { name: "Try again" })).toHaveAttribute("href", "/");
    expect(screen.queryByText(/AUTH_FORBIDDEN/)).not.toBeInTheDocument();
  });
});
