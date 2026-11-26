import { describe, expect, it } from "vitest";

import { isRouteActive } from "./navigation.utils";

describe("isRouteActive", () => {
  it("should mark a module current on its own route", () => {
    expect(isRouteActive("/members", "/members")).toBe(true);
  });

  it("should mark a module current on a page under its route", () => {
    expect(isRouteActive("/members/new", "/members")).toBe(true);
  });

  it("should not mark a module current for a route that only shares its start", () => {
    expect(isRouteActive("/membership", "/members")).toBe(false);
  });

  it("should mark the overview current only on the home route", () => {
    expect(isRouteActive("/", "/")).toBe(true);
    expect(isRouteActive("/members", "/")).toBe(false);
  });
});
