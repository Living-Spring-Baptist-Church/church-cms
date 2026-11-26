import { expect, type Page } from "@playwright/test";

import { LOCAL_DEV_PASSWORD, SEED_STAFF, type SeedStaffKey } from "./seed-staff";
import { generateTotpCode } from "./totp";

const SIGN_IN_TIMEOUT_MILLISECONDS = 30_000;

async function completeTwoFactorEnrolment(page: Page): Promise<void> {
  await page.getByRole("button", { name: "Start setup" }).click();
  const setupKey = await page.getByLabel("Setup key").inputValue();
  await page.getByLabel("Code from your app").fill(generateTotpCode(setupKey));
  await page.getByRole("button", { name: "Finish setup" }).click();
}

/** Signs in through the real login page, enrolling an authenticator when the role needs two-factor. */
export async function signInAs(page: Page, staffKey: SeedStaffKey): Promise<void> {
  const staff = SEED_STAFF[staffKey];
  await page.goto("/login");
  // Filling before React hydrates loses the values, so wait for the page to settle first.
  await page.waitForLoadState("networkidle");
  await page.getByLabel("Email").fill(staff.email);
  await page.getByLabel("Password").fill(LOCAL_DEV_PASSWORD);
  await expect(page.getByLabel("Email")).toHaveValue(staff.email);
  await page.getByRole("button", { name: "Sign in" }).click();
  if (staff.needsTwoFactor) {
    await expect(
      page.getByRole("heading", { name: "Set up two-factor authentication" }),
    ).toBeVisible({ timeout: SIGN_IN_TIMEOUT_MILLISECONDS });
    await completeTwoFactorEnrolment(page);
  }
  await expect(
    page.getByRole("heading", { level: 1, name: `Welcome, ${staff.fullName}` }),
  ).toBeVisible({ timeout: SIGN_IN_TIMEOUT_MILLISECONDS });
}
