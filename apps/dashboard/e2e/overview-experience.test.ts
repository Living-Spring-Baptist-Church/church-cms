import { expect, test } from "@playwright/test";

import {
  CHURCH_NAME,
  isMobileProject,
  mainNavigation,
  readFocusRing,
  tabUntilFocused,
} from "./support/overview-page";
import { authStatePath } from "./support/seed-staff";

const ROUTER_DELAY_MILLISECONDS = 3000;
const NO_FOCUS_RING = "none";

test.describe("overview experience as secretary", () => {
  test.use({ storageState: authStatePath("secretary") });

  test.beforeEach(async ({ page }) => {
    await page.goto("/");
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  });

  test("should reveal the skip link first and move to the main content when pressed", async ({
    page,
  }) => {
    await page.keyboard.press("Tab");
    const skipLink = page.getByRole("link", { name: "Skip to main content" });
    await expect(skipLink).toBeFocused();
    await expect(skipLink).toBeInViewport();
    await page.keyboard.press("Enter");
    await expect(page).toHaveURL(/#main-content$/);
  });

  test("should open the phone menu and show a visible focus ring when using only the keyboard", async ({
    page,
  }, testInfo) => {
    test.skip(!isMobileProject(testInfo), "The phone menu only exists below the md breakpoint");
    const menuToggle = mainNavigation(page).getByText("Menu", { exact: true });
    await tabUntilFocused(page, menuToggle);
    expect(await readFocusRing(menuToggle)).not.toBe(NO_FOCUS_RING);
    await page.keyboard.press("Enter");
    const overviewLink = mainNavigation(page).getByRole("link", { name: "Overview" });
    await expect(overviewLink).toBeVisible();
    await page.keyboard.press("Tab");
    await expect(overviewLink).toBeFocused();
  });

  test("should show a visible focus ring on the overview link when tabbing on desktop", async ({
    page,
  }, testInfo) => {
    test.skip(isMobileProject(testInfo), "Desktop shows the module row");
    const overviewLink = mainNavigation(page).getByRole("link", { name: "Overview" });
    await tabUntilFocused(page, overviewLink);
    expect(await readFocusRing(overviewLink)).not.toBe(NO_FOCUS_RING);
  });

  test("should show skeletons, not a spinner, when the overview is slow to load", async ({
    page,
  }) => {
    await page.goto("/account/security");
    await page.route(/\?_rsc=/, async (route) => {
      await new Promise((resolve) => setTimeout(resolve, ROUTER_DELAY_MILLISECONDS));
      await route.continue();
    });
    await page.getByRole("link", { name: `${CHURCH_NAME} home` }).click();
    await expect(page.locator('[data-slot="skeleton"]').first()).toBeVisible();
    await expect(page.locator('[role="progressbar"], .animate-spin')).toHaveCount(0);
    await expect(page.getByRole("heading", { level: 1, name: /Welcome/ })).toBeVisible();
  });
});
