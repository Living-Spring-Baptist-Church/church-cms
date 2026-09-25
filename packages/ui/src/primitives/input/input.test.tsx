import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

import { Input } from "./input";

const FIELD_LABEL = "First name";

function renderLabelledInput(inputProps: Parameters<typeof Input>[0] = {}) {
  render(
    <label>
      {FIELD_LABEL}
      <Input {...inputProps} />
    </label>,
  );
  return screen.getByRole("textbox", { name: FIELD_LABEL });
}

describe("Input", () => {
  it("should render a text input that is found by its label", () => {
    const firstNameInput = renderLabelledInput();

    expect(firstNameInput).toHaveAttribute("type", "text");
  });

  it("should pass through the type, placeholder and custom class name", () => {
    render(<Input type="email" placeholder="name@example.org" className="max-w-sm" />);

    const emailInput = screen.getByPlaceholderText("name@example.org");
    expect(emailInput).toHaveAttribute("type", "email");
    expect(emailInput).toHaveClass("max-w-sm", "border-input");
  });

  it("should call onChange and show each typed character", async () => {
    const handleChange = vi.fn();
    const firstNameInput = renderLabelledInput({ onChange: handleChange });

    await userEvent.type(firstNameInput, "Ama");

    expect(firstNameInput).toHaveValue("Ama");
    expect(handleChange).toHaveBeenCalledTimes("Ama".length);
  });

  it("should ignore typing when disabled", async () => {
    const firstNameInput = renderLabelledInput({ disabled: true });

    await userEvent.type(firstNameInput, "Ama");

    expect(firstNameInput).toBeDisabled();
    expect(firstNameInput).toHaveValue("");
  });

  it("should expose an invalid state to assistive technology", () => {
    const firstNameInput = renderLabelledInput({ "aria-invalid": true });

    expect(firstNameInput).toBeInvalid();
  });
});
