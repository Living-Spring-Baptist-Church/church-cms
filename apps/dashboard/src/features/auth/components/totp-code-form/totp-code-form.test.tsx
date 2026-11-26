import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

import {
  fillServerForm,
  renderServerForm,
  resolveNativeSubmissionUrl,
} from "@test/native-form-submission";

import { TotpCodeForm } from "./totp-code-form";

const WRONG_CODE = {
  ok: false,
  error: { code: "invalid_code", message: "That code is not correct. Try again." },
} as const;

function renderForm(submitCode = vi.fn().mockResolvedValue(WRONG_CODE)) {
  render(
    <TotpCodeForm
      label="Authentication code"
      hint="Six digits"
      submitLabel="Verify"
      pendingLabel="Verifying"
      submitCode={submitCode}
    />,
  );
  return submitCode;
}

describe("TotpCodeForm", () => {
  it("should offer a numeric one time code field", () => {
    renderForm();

    const codeInput = screen.getByLabelText("Authentication code");
    expect(codeInput).toHaveAttribute("inputmode", "numeric");
    expect(codeInput).toHaveAttribute("autocomplete", "one-time-code");
    expect(codeInput).toHaveAccessibleDescription("Six digits");
  });

  it("should keep only digits while typing", async () => {
    renderForm();

    await userEvent.type(screen.getByLabelText("Authentication code"), "12a-34");

    expect(screen.getByLabelText("Authentication code")).toHaveValue("1234");
  });

  it("should accept a pasted code with a space and keep six digits", async () => {
    const submitCode = renderForm();

    await userEvent.click(screen.getByLabelText("Authentication code"));
    await userEvent.paste("123 456 789");

    expect(screen.getByLabelText("Authentication code")).toHaveValue("123456");
    await userEvent.click(screen.getByRole("button", { name: "Verify" }));
    await waitFor(() => {
      expect(submitCode).toHaveBeenCalledWith({ code: "123456" });
    });
  });

  it("should submit a valid code", async () => {
    const submitCode = renderForm();

    await userEvent.type(screen.getByLabelText("Authentication code"), "123456");
    await userEvent.click(screen.getByRole("button", { name: "Verify" }));

    await waitFor(() => {
      expect(submitCode).toHaveBeenCalledWith({ code: "123456" });
    });
  });

  it("should show the friendly message and clear the field after a wrong code", async () => {
    renderForm();

    await userEvent.type(screen.getByLabelText("Authentication code"), "000000");
    await userEvent.click(screen.getByRole("button", { name: "Verify" }));

    expect(await screen.findByText("That code is not correct. Try again.")).toBeInTheDocument();
    expect(screen.getByLabelText("Authentication code")).toHaveValue("");
  });

  it("should show an inline error for a short code without calling the server", async () => {
    const submitCode = renderForm();

    await userEvent.type(screen.getByLabelText("Authentication code"), "12");
    await userEvent.click(screen.getByRole("button", { name: "Verify" }));

    expect(await screen.findByText("Enter the 6 digit code from your app.")).toBeInTheDocument();
    expect(submitCode).not.toHaveBeenCalled();
  });

  it("should work without a hint", () => {
    render(
      <TotpCodeForm
        label="Code"
        submitLabel="Verify"
        pendingLabel="Verifying"
        submitCode={vi.fn()}
      />,
    );

    expect(screen.getByLabelText("Code")).toHaveAccessibleDescription("");
  });

  it("should post a submit made before hydration so the code never reaches the URL", () => {
    const serverForm = renderServerForm(
      <TotpCodeForm
        label="Code"
        submitLabel="Verify"
        pendingLabel="Verifying"
        submitCode={vi.fn()}
      />,
    );
    fillServerForm(serverForm, { code: "123456" });

    const submissionUrl = resolveNativeSubmissionUrl(serverForm);

    expect(serverForm.method).toBe("post");
    expect(submissionUrl.search).toBe("");
    expect(submissionUrl.href).not.toContain("123456");
  });

  it("should handle the submit in the page instead of navigating once hydrated", () => {
    renderForm();
    const form = screen.getByRole("button", { name: "Verify" }).closest("form");

    expect(form).toHaveAttribute("method", "post");
    expect(fireEvent.submit(form as HTMLFormElement)).toBe(false);
  });
});
