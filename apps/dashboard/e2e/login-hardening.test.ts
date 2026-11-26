import { expect, test } from "@playwright/test";

import { LOCAL_DEV_PASSWORD, SEED_STAFF } from "./support/seed-staff";

// A phone on a slow network can show the login form before React hydrates. Submitting then must
// never put the password in the address bar, browser history, server logs or a Referer header.
test.describe("login form before hydration", () => {
  test.use({ javaScriptEnabled: false });

  test("should never put the password in the URL when the form is submitted before JavaScript runs", async ({
    page,
  }) => {
    await page.goto("/login");
    await page.getByLabel("Email").fill(SEED_STAFF.usher.email);
    await page.getByLabel("Password").fill(LOCAL_DEV_PASSWORD);
    await page.getByRole("button", { name: "Sign in" }).click();
    await page.waitForLoadState("domcontentloaded");
    expect(page.url()).not.toContain("password=");
    expect(page.url()).not.toContain(encodeURIComponent(LOCAL_DEV_PASSWORD));
  });
});
