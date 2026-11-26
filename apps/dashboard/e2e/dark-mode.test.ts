import { expect, test, type Page } from "@playwright/test";

import { CHURCH_NAME, expectNoAxeViolations, revealMainNavigation } from "./support/overview-page";
import { authStatePath } from "./support/seed-staff";
import {
  DARK_SURFACE_MAX_LUMINANCE,
  hasDarkThemeClass,
  readBackgroundLuminance,
  readDarkClassAtFirstBody,
  readPageBackground,
  recordDarkClassAtFirstBody,
} from "./support/theme";

const LIGHT_PAGE_BACKGROUND = "rgb(255, 255, 255)";

async function openOverview(page: Page): Promise<void> {
  await page.goto("/");
  await expect(page.getByRole("heading", { level: 1, name: /Welcome/ })).toBeVisible();
}

test.describe("dark mode as secretary", () => {
  test.use({ storageState: authStatePath("secretary") });

  test("should paint dark from the first frame when the device prefers dark", async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on("console", (message) => {
      if (message.type() === "error") {
        consoleErrors.push(message.text());
      }
    });
    await page.emulateMedia({ colorScheme: "dark" });
    await recordDarkClassAtFirstBody(page);
    await openOverview(page);
    expect(await readDarkClassAtFirstBody(page)).toBe("true");
    expect(consoleErrors).toEqual([]);
    expect(await hasDarkThemeClass(page)).toBe(true);
    const pageBackground = page.locator("body");
    expect(await readBackgroundLuminance(pageBackground)).toBeLessThan(DARK_SURFACE_MAX_LUMINANCE);
  });

  test("should stay light when the device prefers light", async ({ page }) => {
    await page.emulateMedia({ colorScheme: "light" });
    await recordDarkClassAtFirstBody(page);
    await openOverview(page);
    expect(await readDarkClassAtFirstBody(page)).toBe("false");
    expect(await readPageBackground(page)).toBe(LIGHT_PAGE_BACKGROUND);
  });

  test("should switch theme without a reload when the device setting changes while open", async ({
    page,
  }) => {
    await page.emulateMedia({ colorScheme: "light" });
    await openOverview(page);
    expect(await hasDarkThemeClass(page)).toBe(false);
    await page.emulateMedia({ colorScheme: "dark" });
    await expect.poll(() => hasDarkThemeClass(page)).toBe(true);
    expect(await readPageBackground(page)).not.toBe(LIGHT_PAGE_BACKGROUND);
    await page.emulateMedia({ colorScheme: "light" });
    await expect.poll(() => hasDarkThemeClass(page)).toBe(false);
    expect(await readPageBackground(page)).toBe(LIGHT_PAGE_BACKGROUND);
  });

  for (const colorScheme of ["light", "dark"] as const) {
    test(`should keep the header navy with the church name when the device prefers ${colorScheme}`, async ({
      page,
    }) => {
      await page.emulateMedia({ colorScheme });
      await openOverview(page);
      const banner = page.getByRole("banner");
      await expect(banner.getByText(CHURCH_NAME, { exact: true })).toBeVisible();
      expect(await readBackgroundLuminance(banner)).toBeLessThan(DARK_SURFACE_MAX_LUMINANCE);
    });
  }

  test("should have no axe violations on the overview and its menu when the device prefers dark", async ({
    page,
  }, testInfo) => {
    await page.emulateMedia({ colorScheme: "dark" });
    await openOverview(page);
    await expectNoAxeViolations(page);
    await revealMainNavigation(page, testInfo);
    await expectNoAxeViolations(page);
  });

  test("should have no axe violations on account security when the device prefers dark", async ({
    page,
  }) => {
    await page.emulateMedia({ colorScheme: "dark" });
    await page.goto("/account/security");
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    await expectNoAxeViolations(page);
  });
});

test.describe("dark mode empty overview as content editor", () => {
  test.use({ storageState: authStatePath("contentEditor") });

  test("should have no axe violations on the empty overview when the device prefers dark", async ({
    page,
  }) => {
    await page.emulateMedia({ colorScheme: "dark" });
    await openOverview(page);
    await expect(page.getByText("No figures are shown for your roles yet.")).toBeVisible();
    await expectNoAxeViolations(page);
  });
});

test.describe("dark mode signed out", () => {
  test("should have no axe violations on the login page when the device prefers dark", async ({
    page,
  }) => {
    await page.emulateMedia({ colorScheme: "dark" });
    await page.goto("/login");
    await expect(page.getByRole("button", { name: "Sign in" })).toBeVisible();
    expect(await hasDarkThemeClass(page)).toBe(true);
    await expectNoAxeViolations(page);
  });
});
