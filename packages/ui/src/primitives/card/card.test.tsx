import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

import { Button } from "#primitives/button/button";

import { Card } from "./card";
import { CardContent } from "./card-content";
import { CardDescription } from "./card-description";
import { CardFooter } from "./card-footer";
import { CardHeader } from "./card-header";
import { CardTitle } from "./card-title";

type SampleCardProps = {
  onAction?: () => void;
  titleLevel?: "h2" | "h3" | "h4";
};

function SampleCard({ onAction, titleLevel }: SampleCardProps) {
  return (
    <Card className="max-w-md">
      <CardHeader>
        <CardTitle as={titleLevel}>Sunday service</CardTitle>
        <CardDescription>Main auditorium</CardDescription>
      </CardHeader>
      <CardContent>
        <p>Worship starts at nine.</p>
      </CardContent>
      <CardFooter>
        <Button onClick={onAction}>Record attendance</Button>
      </CardFooter>
    </Card>
  );
}

describe("Card", () => {
  it("should render every part of the card", () => {
    render(<SampleCard />);

    expect(screen.getByRole("heading", { name: "Sunday service" })).toBeInTheDocument();
    expect(screen.getByText("Main auditorium")).toBeInTheDocument();
    expect(screen.getByText("Worship starts at nine.")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Record attendance" })).toBeInTheDocument();
  });

  it("should render the title as an h3 by default", () => {
    render(<SampleCard />);

    expect(screen.getByRole("heading", { level: 3, name: "Sunday service" })).toBeInTheDocument();
  });

  it("should render the title at the heading level passed in", () => {
    render(<SampleCard titleLevel="h2" />);

    expect(screen.getByRole("heading", { level: 2, name: "Sunday service" })).toBeInTheDocument();
  });

  it("should apply card surface tokens and merge a custom class name", () => {
    const { container } = render(<SampleCard />);

    const cardRoot = container.firstElementChild;
    expect(cardRoot).toHaveClass("bg-card", "text-card-foreground", "max-w-md");
  });

  it("should fire the footer action when its button is clicked", async () => {
    const handleAction = vi.fn();
    render(<SampleCard onAction={handleAction} />);

    await userEvent.click(screen.getByRole("button", { name: "Record attendance" }));

    expect(handleAction).toHaveBeenCalledOnce();
  });
});
