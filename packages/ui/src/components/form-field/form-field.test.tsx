import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";

import { FormField } from "./form-field";

describe("FormField", () => {
  it("should label the input", () => {
    render(<FormField label="Email" type="email" />);

    expect(screen.getByLabelText("Email")).toHaveAttribute("type", "email");
  });

  it("should link the hint to the input", () => {
    render(<FormField label="Code" hint="Six digits" />);

    expect(screen.getByLabelText("Code")).toHaveAccessibleDescription("Six digits");
  });

  it("should show the error with the input marked invalid", () => {
    render(<FormField label="Email" error="Enter a valid email address." />);

    const emailInput = screen.getByLabelText("Email");
    expect(emailInput).toBeInvalid();
    expect(emailInput).toHaveAccessibleDescription("Enter a valid email address.");
  });

  it("should not be invalid and show nothing without an error", () => {
    render(<FormField label="Email" error="" />);

    expect(screen.getByLabelText("Email")).toBeValid();
    expect(screen.getByLabelText("Email")).toHaveAccessibleDescription("");
  });

  it("should use a given id and accept typing", async () => {
    render(<FormField label="Name" id="staff-name" />);

    await userEvent.type(screen.getByLabelText("Name"), "Ama");

    expect(screen.getByLabelText("Name")).toHaveAttribute("id", "staff-name");
    expect(screen.getByLabelText("Name")).toHaveValue("Ama");
  });
});
