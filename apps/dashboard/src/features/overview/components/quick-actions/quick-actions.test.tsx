import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import type { RoleGatedLink } from "@core/types/navigation.types";

import { QuickActions } from "./quick-actions";

const BUILT_ACTION: RoleGatedLink = {
  id: "recordAttendance",
  label: "Record attendance",
  href: "/attendance",
  isAvailable: true,
  allowedRoles: ["usher"],
};

const UNBUILT_ACTION: RoleGatedLink = {
  id: "recordOffering",
  label: "Record offering",
  href: "/finance",
  isAvailable: false,
  allowedRoles: ["treasurer"],
};

describe("QuickActions", () => {
  it("should link a built action to its route", () => {
    render(<QuickActions actions={[BUILT_ACTION]} />);

    expect(screen.getByRole("link", { name: "Record attendance" })).toHaveAttribute(
      "href",
      "/attendance",
    );
  });

  it("should show an unbuilt action as a disabled button with a note, never as a link", () => {
    render(<QuickActions actions={[UNBUILT_ACTION]} />);

    expect(screen.getByRole("button", { name: "Record offering" })).toBeDisabled();
    expect(screen.getByText("Not available yet")).toBeInTheDocument();
    expect(screen.queryByRole("link", { name: "Record offering" })).not.toBeInTheDocument();
  });

  it("should render nothing when the role has no quick action", () => {
    render(<QuickActions actions={[]} />);

    expect(screen.queryByRole("heading", { name: "Quick actions" })).not.toBeInTheDocument();
  });
});
