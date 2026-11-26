import type { ReactElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";

const POST_METHOD = "post";
const HTML_MIME_TYPE = "text/html";

/** The form exactly as the server sends it, before React hydrates and attaches any handler. */
export function renderServerForm(element: ReactElement): HTMLFormElement {
  const markup = renderToStaticMarkup(element);
  const form = new DOMParser().parseFromString(markup, HTML_MIME_TYPE).querySelector("form");
  if (form === null) {
    throw new Error("The rendered markup contains no form.");
  }
  return form;
}

/** Types into named fields the way a user would before the page scripts have loaded. */
export function fillServerForm(
  form: HTMLFormElement,
  valuesByFieldName: Readonly<Record<string, string>>,
): void {
  for (const [fieldName, fieldValue] of Object.entries(valuesByFieldName)) {
    const field = form.querySelector<HTMLInputElement>(`input[name="${fieldName}"]`);
    if (field === null) {
      throw new Error(`The form has no input named ${fieldName}.`);
    }
    field.value = fieldValue;
  }
}

/** The URL the browser navigates to on a native submit, following the HTML form submission rules. */
export function resolveNativeSubmissionUrl(form: HTMLFormElement): URL {
  const submitter = form.querySelector<HTMLButtonElement>('button[type="submit"]');
  const method = submitter?.getAttribute("formmethod") ?? form.getAttribute("method") ?? "";
  const target = new URL(submitter?.getAttribute("formaction") ?? form.action);
  if (method.toLowerCase() !== POST_METHOD) {
    const textFields = [...new FormData(form).entries()].filter(
      (entry): entry is [string, string] => typeof entry[1] === "string",
    );
    target.search = new URLSearchParams(textFields).toString();
  }
  return target;
}
