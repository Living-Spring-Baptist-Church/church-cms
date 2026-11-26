import { render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import type { RoleGatedLink } from "@core/types/navigation.types";

import { AppNav } from "./app-nav";

const mocks = vi.hoisted(() => ({ pathname: "/" }));

vi.mock("next/navigation", () => ({ usePathname: () => mocks.pathname }));

const MODULES: readonly RoleGatedLink[] = [
  { id: "overview", label: "Overview", href: "/", isAvailable: true, allowedRoles: ["usher"] },
  {
    id: "members",
    label: "Members",
    href: "/members",
    isAvailable: false,
    allowedRoles: ["usher"],
  },
];

beforeEach(() => {
  mocks.pathname = "/";
});

describe("AppNav", () => {
  it("should label the navigation as the main navigation", () => {
    render(<AppNav modules={MODULES} />);

    expect(screen.getByRole("navigation", { name: "Main" })).toBeInTheDocument();
  });

  it("should link a built module to its route", () => {
    render(<AppNav modules={MODULES} />);

    expect(screen.getAllByRole("link", { name: "Overview" })[0]).toHaveAttribute("href", "/");
  });

  it("should show an unbuilt module as text with a note, not as a link", () => {
    render(<AppNav modules={MODULES} />);

    expect(screen.queryByRole("link", { name: "Members" })).not.toBeInTheDocument();
    expect(screen.getAllByText("Members")[0]).toBeInTheDocument();
    expect(screen.getAllByText("Not available yet")[0]).toBeInTheDocument();
  });

  it("should offer the menu on phones through a disclosure", () => {
    render(<AppNav modules={MODULES} />);

    expect(screen.getByText("Menu").closest("details")).not.toBeNull();
  });

  it("should render no link when the user may use no module", () => {
    render(<AppNav modules={[]} />);

    expect(screen.queryByRole("link")).not.toBeInTheDocument();
  });
});
