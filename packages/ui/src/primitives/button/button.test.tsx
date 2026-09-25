import { createEvent, fireEvent, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

import { Button } from "./button";

describe("Button", () => {
  it("should render a button with its label", () => {
    render(<Button>Save</Button>);

    expect(screen.getByRole("button", { name: "Save" })).toBeInTheDocument();
  });

  it("should default to type button so it never submits a form by accident", () => {
    render(<Button>Save</Button>);

    expect(screen.getByRole("button", { name: "Save" })).toHaveAttribute("type", "button");
  });

  it("should use the primary colours for the default variant", () => {
    render(<Button>Save</Button>);

    expect(screen.getByRole("button", { name: "Save" })).toHaveClass("bg-primary", "h-11");
  });

  it("should change its classes when the variant and size change", () => {
    render(
      <Button variant="destructive" size="lg">
        Delete
      </Button>,
    );

    const deleteButton = screen.getByRole("button", { name: "Delete" });
    expect(deleteButton).toHaveClass("bg-destructive", "h-12");
    expect(deleteButton).not.toHaveClass("bg-primary");
  });

  it("should merge a custom class name, letting it override a conflicting default", () => {
    render(<Button className="px-8">Save</Button>);

    const saveButton = screen.getByRole("button", { name: "Save" });
    expect(saveButton).toHaveClass("px-8");
    expect(saveButton).not.toHaveClass("px-4");
  });

  it("should call onClick when clicked", async () => {
    const handleClick = vi.fn();
    render(<Button onClick={handleClick}>Save</Button>);

    await userEvent.click(screen.getByRole("button", { name: "Save" }));

    expect(handleClick).toHaveBeenCalledOnce();
  });

  it("should not call onClick when disabled", async () => {
    const handleClick = vi.fn();
    render(
      <Button disabled onClick={handleClick}>
        Save
      </Button>,
    );

    await userEvent.click(screen.getByRole("button", { name: "Save" }));

    expect(handleClick).not.toHaveBeenCalled();
  });

  it("should render its child element with button styles when asChild is set", () => {
    render(
      <Button asChild variant="outline">
        <a href="/members">Members</a>
      </Button>,
    );

    const membersLink = screen.getByRole("link", { name: "Members" });
    expect(membersLink).toHaveClass("border-input");
    expect(membersLink).not.toHaveAttribute("type");
    expect(screen.queryByRole("button")).not.toBeInTheDocument();
  });

  it("should mark an asChild link as disabled and take it out of the tab order", async () => {
    render(
      <>
        <Button asChild disabled>
          <a href="/members">Members</a>
        </Button>
        <Button>Save</Button>
      </>,
    );

    const membersLink = screen.getByRole("link", { name: "Members" });
    expect(membersLink).toHaveAttribute("aria-disabled", "true");
    expect(membersLink).toHaveAttribute("tabindex", "-1");
    expect(membersLink).toHaveClass("pointer-events-none", "opacity-50");
    expect(membersLink).not.toHaveAttribute("disabled");

    await userEvent.tab();

    expect(screen.getByRole("button", { name: "Save" })).toHaveFocus();
  });

  it("should block a synthetic click on a disabled asChild link, including the Button onClick", () => {
    const handleButtonClick = vi.fn();
    const handleAncestorClick = vi.fn();
    render(
      // eslint-disable-next-line jsx-a11y/click-events-have-key-events, jsx-a11y/no-static-element-interactions -- listener only observes propagation in the test
      <div onClick={handleAncestorClick}>
        <Button asChild disabled onClick={handleButtonClick}>
          <a href="/members">Members</a>
        </Button>
      </div>,
    );
    const membersLink = screen.getByRole("link", { name: "Members" });
    const clickEvent = createEvent.click(membersLink);

    fireEvent(membersLink, clickEvent);

    expect(clickEvent.defaultPrevented).toBe(true);
    expect(handleButtonClick).not.toHaveBeenCalled();
    expect(handleAncestorClick).not.toHaveBeenCalled();
  });

  it("should block a synthetic click on a disabled asChild link that has its own onClick", () => {
    const handleLinkClick = vi.fn();
    render(
      <Button asChild disabled>
        <a href="/members" onClick={handleLinkClick}>
          Members
        </a>
      </Button>,
    );
    const membersLink = screen.getByRole("link", { name: "Members" });
    const clickEvent = createEvent.click(membersLink);

    fireEvent(membersLink, clickEvent);

    expect(clickEvent.defaultPrevented).toBe(true);
    expect(handleLinkClick).not.toHaveBeenCalled();
  });

  it("should let a synthetic click through on an enabled asChild link", () => {
    const handleButtonClick = vi.fn();
    render(
      <Button asChild onClick={handleButtonClick}>
        <a href="/members">Members</a>
      </Button>,
    );
    const membersLink = screen.getByRole("link", { name: "Members" });
    const clickEvent = createEvent.click(membersLink);

    fireEvent(membersLink, clickEvent);

    expect(handleButtonClick).toHaveBeenCalledOnce();
    // jsdom does not navigate, so this only proves the Button left the default action alone.
    expect(clickEvent.defaultPrevented).toBe(false);
  });

  it("should leave an enabled asChild link focusable", () => {
    render(
      <Button asChild>
        <a href="/members">Members</a>
      </Button>,
    );

    const membersLink = screen.getByRole("link", { name: "Members" });
    expect(membersLink).not.toHaveAttribute("aria-disabled");
    expect(membersLink).not.toHaveAttribute("tabindex");
    expect(membersLink).not.toHaveClass("pointer-events-none");
  });
});
