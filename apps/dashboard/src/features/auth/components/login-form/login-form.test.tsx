import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

import { LoginForm } from "./login-form";

const GENERIC_FAILURE = {
  ok: false,
  error: { code: "invalid_credentials", message: "Email or password is incorrect." },
} as const;

function renderForm(signIn = vi.fn().mockResolvedValue(GENERIC_FAILURE)) {
  render(<LoginForm signIn={signIn} />);
  return signIn;
}

describe("LoginForm", () => {
  it("should label both fields and set the autocomplete hints password managers use", () => {
    renderForm();

    expect(screen.getByLabelText("Email")).toHaveAttribute("autocomplete", "username");
    expect(screen.getByLabelText("Password")).toHaveAttribute("autocomplete", "current-password");
    expect(screen.getByLabelText("Password")).toHaveAttribute("type", "password");
  });

  it("should submit the trimmed email and the password", async () => {
    const signIn = renderForm();

    await userEvent.type(screen.getByLabelText("Email"), " staff@example.org ");
    await userEvent.type(screen.getByLabelText("Password"), "a-password");
    await userEvent.click(screen.getByRole("button", { name: "Sign in" }));

    await waitFor(() => {
      expect(signIn).toHaveBeenCalledWith({ email: "staff@example.org", password: "a-password" });
    });
  });

  it("should show the generic server message in an announced alert", async () => {
    renderForm();

    await userEvent.type(screen.getByLabelText("Email"), "staff@example.org");
    await userEvent.type(screen.getByLabelText("Password"), "wrong");
    await userEvent.click(screen.getByRole("button", { name: "Sign in" }));

    expect(await screen.findByText("Email or password is incorrect.")).toBeInTheDocument();
  });

  it("should show inline errors and not call the server for empty fields", async () => {
    const signIn = renderForm();

    await userEvent.click(screen.getByRole("button", { name: "Sign in" }));

    expect(await screen.findByText("Enter a valid email address.")).toBeInTheDocument();
    expect(screen.getByText("Enter your password.")).toBeInTheDocument();
    expect(screen.getByLabelText("Email")).toBeInvalid();
    expect(signIn).not.toHaveBeenCalled();
  });

  it("should disable the button while the sign in is running", async () => {
    let finish: (value: typeof GENERIC_FAILURE) => void = () => undefined;
    const signIn = vi.fn(
      () =>
        new Promise<typeof GENERIC_FAILURE>((resolve) => {
          finish = resolve;
        }),
    );
    renderForm(signIn);

    await userEvent.type(screen.getByLabelText("Email"), "staff@example.org");
    await userEvent.type(screen.getByLabelText("Password"), "a-password");
    await userEvent.click(screen.getByRole("button", { name: "Sign in" }));

    expect(await screen.findByRole("button", { name: "Signing in" })).toBeDisabled();
    finish(GENERIC_FAILURE);
    expect(await screen.findByRole("button", { name: "Sign in" })).toBeEnabled();
  });
});
