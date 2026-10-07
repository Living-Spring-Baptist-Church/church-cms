import { render } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { Skeleton } from "./skeleton";

describe("Skeleton", () => {
  it("should be hidden from assistive technology", () => {
    const { container } = render(<Skeleton />);

    expect(container.firstElementChild).toHaveAttribute("aria-hidden", "true");
  });

  it("should take its size from the class name and pulse only when motion is allowed", () => {
    const { container } = render(<Skeleton className="h-10 w-full" />);

    expect(container.firstElementChild).toHaveClass("h-10", "w-full", "motion-safe:animate-pulse");
  });
});
