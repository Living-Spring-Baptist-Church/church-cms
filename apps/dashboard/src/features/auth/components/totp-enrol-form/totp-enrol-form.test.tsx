import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

import { TotpEnrolForm } from "./totp-enrol-form";

const ENROLMENT = {
  factorId: "factor-1",
  qrCodeDataUri: "data:image/svg+xml;utf-8,<svg xmlns='http://www.w3.org/2000/svg'/>",
  secret: "JBSWY3DPEHPK3PXP",
};

const WRONG_CODE = {
  ok: false,
  error: { code: "invalid_code", message: "That code is not correct. Try again." },
} as const;

function renderForm(overrides: Partial<Parameters<typeof TotpEnrolForm>[0]> = {}) {
  const startEnrolment = vi.fn().mockResolvedValue({ ok: true, data: ENROLMENT });
  const confirmEnrolment = vi.fn().mockResolvedValue(WRONG_CODE);
  render(
    <TotpEnrolForm
      startEnrolment={startEnrolment}
      confirmEnrolment={confirmEnrolment}
      {...overrides}
    />,
  );
  return { startEnrolment, confirmEnrolment };
}

async function startSetup() {
  await userEvent.click(screen.getByRole("button", { name: "Start setup" }));
  await screen.findByRole("img", { name: /QR code/ });
}

describe("TotpEnrolForm", () => {
  it("should not request a secret until the person starts the setup", () => {
    const { startEnrolment } = renderForm();

    expect(screen.getByRole("button", { name: "Start setup" })).toBeEnabled();
    expect(startEnrolment).not.toHaveBeenCalled();
  });

  it("should show the QR code with alt text and the manual setup key", async () => {
    renderForm();

    await startSetup();

    expect(screen.getByRole("img", { name: /QR code/ })).toBeInTheDocument();
    expect(screen.getByLabelText("Setup key")).toHaveValue(ENROLMENT.secret);
    expect(screen.getByLabelText("Setup key")).toHaveAttribute("readonly");
  });

  it("should copy the setup key and say so", async () => {
    renderForm();
    const writeText = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, "clipboard", { value: { writeText }, configurable: true });
    await startSetup();

    await userEvent.click(screen.getByRole("button", { name: "Copy key" }));

    expect(writeText).toHaveBeenCalledWith(ENROLMENT.secret);
    expect(await screen.findByRole("button", { name: "Key copied" })).toBeInTheDocument();
  });

  it("should confirm the enrolment with the factor and the entered code", async () => {
    const { confirmEnrolment } = renderForm();
    await startSetup();

    await userEvent.type(screen.getByLabelText("Code from your app"), "123456");
    await userEvent.click(screen.getByRole("button", { name: "Finish setup" }));

    await waitFor(() => {
      expect(confirmEnrolment).toHaveBeenCalledWith({ factorId: "factor-1", code: "123456" });
    });
    expect(await screen.findByText("That code is not correct. Try again.")).toBeInTheDocument();
  });

  it("should show a plain error and keep the start button when setup cannot start", async () => {
    renderForm({
      startEnrolment: vi.fn().mockResolvedValue({
        ok: false,
        error: {
          code: "server",
          message: "Something went wrong on our side. Try again in a moment.",
        },
      }),
    });

    await userEvent.click(screen.getByRole("button", { name: "Start setup" }));

    expect(await screen.findByText(/Something went wrong on our side/)).toBeInTheDocument();
    expect(await screen.findByRole("button", { name: "Start setup" })).toBeEnabled();
  });
});
