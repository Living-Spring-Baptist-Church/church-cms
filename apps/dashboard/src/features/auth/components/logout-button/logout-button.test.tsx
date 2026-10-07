import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

import { LogoutButton } from "./logout-button";

describe("LogoutButton", () => {
  it("should render a sign out button inside a form", () => {
    render(<LogoutButton signOut={vi.fn()} />);

    const button = screen.getByRole("button", { name: "Sign out" });
    expect(button).toHaveAttribute("type", "submit");
    expect(button.closest("form")).not.toBeNull();
  });

  it("should call the sign out action when pressed", async () => {
    const signOut = vi.fn().mockResolvedValue(undefined);
    render(<LogoutButton signOut={signOut} />);

    await userEvent.click(screen.getByRole("button", { name: "Sign out" }));

    await waitFor(() => {
      expect(signOut).toHaveBeenCalledTimes(1);
    });
  });

  it("should accept a variant and a class name", () => {
    render(<LogoutButton signOut={vi.fn()} variant="ghost" className="mt-2" />);

    expect(screen.getByRole("button", { name: "Sign out" })).toHaveClass("mt-2");
  });
});
