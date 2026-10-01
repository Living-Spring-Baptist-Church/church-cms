import { describe, expect, it } from "vitest";

import { cn } from "./cn.utils";

describe("cn", () => {
  it("should join class names", () => {
    expect(cn("flex", "gap-2")).toBe("flex gap-2");
  });

  it("should drop falsy values", () => {
    expect(cn("flex", false, undefined, null, "")).toBe("flex");
  });

  it("should include a class only when its condition is true", () => {
    const buildRowClassName = (isSelected: boolean) => cn("flex", isSelected && "bg-accent");

    expect(buildRowClassName(true)).toBe("flex bg-accent");
    expect(buildRowClassName(false)).toBe("flex");
  });

  it("should let a later Tailwind class win over a conflicting earlier one", () => {
    expect(cn("px-4 bg-primary", "px-6 bg-destructive")).toBe("px-6 bg-destructive");
  });

  it("should return an empty string when given nothing", () => {
    expect(cn()).toBe("");
  });
});
