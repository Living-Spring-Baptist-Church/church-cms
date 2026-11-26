import { describe, expect, it } from "vitest";

import {
  fillServerForm,
  renderServerForm,
  resolveNativeSubmissionUrl,
} from "./native-form-submission";

const SECRET = "a-secret";

describe("resolveNativeSubmissionUrl", () => {
  it("should put the fields in the URL for a form with no method, as browsers do", () => {
    const form = renderServerForm(
      <form>
        <input name="password" />
        <button type="submit">Send</button>
      </form>,
    );
    fillServerForm(form, { password: SECRET });

    expect(resolveNativeSubmissionUrl(form).searchParams.get("password")).toBe(SECRET);
  });

  it("should keep the fields out of the URL for a POST form", () => {
    const form = renderServerForm(
      <form method="post">
        <input name="password" />
        <button type="submit">Send</button>
      </form>,
    );
    fillServerForm(form, { password: SECRET });

    expect(resolveNativeSubmissionUrl(form).search).toBe("");
  });

  it("should honour a submit button that switches the form back to GET", () => {
    const form = renderServerForm(
      <form method="post">
        <input name="password" />
        <button type="submit" formMethod="get">
          Send
        </button>
      </form>,
    );
    fillServerForm(form, { password: SECRET });

    expect(resolveNativeSubmissionUrl(form).searchParams.get("password")).toBe(SECRET);
  });

  it("should fail loudly when the markup has no form or the field does not exist", () => {
    expect(() => renderServerForm(<p>No form</p>)).toThrow("no form");

    const form = renderServerForm(<form method="post" />);
    expect(() => {
      fillServerForm(form, { password: SECRET });
    }).toThrow("no input named password");
  });
});
