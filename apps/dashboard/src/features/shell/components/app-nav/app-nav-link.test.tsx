import { render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { AppNavLink } from "./app-nav-link";

const mocks = vi.hoisted(() => ({ pathname: "/" }));

vi.mock("next/navigation", () => ({ usePathname: () => mocks.pathname }));

beforeEach(() => {
  mocks.pathname = "/";
});

describe("AppNavLink", () => {
  it("should mark the link as the current page when the path is its route", () => {
    mocks.pathname = "/members";
    render(<AppNavLink href="/members" label="Members" />);

    expect(screen.getByRole("link", { name: "Members" })).toHaveAttribute("aria-current", "page");
  });

  it("should not mark the link as current for another route", () => {
    mocks.pathname = "/";
    render(<AppNavLink href="/members" label="Members" />);

    expect(screen.getByRole("link", { name: "Members" })).not.toHaveAttribute("aria-current");
  });
});
