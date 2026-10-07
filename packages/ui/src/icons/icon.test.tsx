import { render } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { Icon, type IconName } from "./icon";

const ICON_NAMES: readonly IconName[] = [
  "check",
  "circle-alert",
  "copy",
  "info",
  "log-out",
  "shield-check",
];

describe("Icon", () => {
  it.each(ICON_NAMES)("should render %s as a decorative svg", (name) => {
    const { container } = render(<Icon name={name} />);

    const icon = container.querySelector("svg");
    expect(icon).toHaveAttribute("aria-hidden", "true");
    expect(icon).toHaveClass("size-4");
  });

  it("should merge a custom class name", () => {
    const { container } = render(<Icon name="check" className="size-6 text-success" />);

    expect(container.querySelector("svg")).toHaveClass("size-6", "text-success");
  });
});
