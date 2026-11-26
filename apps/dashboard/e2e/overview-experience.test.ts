import { expect, test, type Page } from "@playwright/test";

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
const RSC_REQUEST_PATTERN = /\?_rsc=/;
const PREFETCH_HEADER = "next-router-prefetch";
const OVERVIEW_PATH = "/";

function isPrefetchRequest(headers: Readonly<Record<string, string>>): boolean {
  return headers[PREFETCH_HEADER] === "1";
}

/**
 * Slows every navigation fetch while letting link prefetches through. The skeleton comes from the
 * loading boundary in the overview prefetch, so a delayed prefetch would leave no skeleton to show.
 * Returns a counter so the test can prove the navigation really went through the slow path.
 */
async function slowDownNavigations(page: Page): Promise<{ readonly count: () => number }> {
  let delayedNavigations = 0;
  await page.route(RSC_REQUEST_PATTERN, async (route) => {
    if (!isPrefetchRequest(route.request().headers())) {
      delayedNavigations += 1;
      await new Promise((resolve) => setTimeout(resolve, ROUTER_DELAY_MILLISECONDS));
    }
    await route.continue();
  });
  return { count: () => delayedNavigations };
}

async function waitForOverviewPrefetch(page: Page): Promise<void> {
  await page.waitForResponse(
    (response) =>
      new URL(response.url()).pathname === OVERVIEW_PATH &&
      isPrefetchRequest(response.request().headers()),
  );
  // The overview prefetch arrives in more than one request; let them all settle before clicking.
  await page.waitForLoadState("networkidle");
}

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
    const delayedNavigations = await slowDownNavigations(page);
    const overviewPrefetch = waitForOverviewPrefetch(page);
    await page.goto("/account/security");
    await overviewPrefetch;
    await page.getByRole("link", { name: `${CHURCH_NAME} home` }).click();
    await expect(page.locator('[data-slot="skeleton"]').first()).toBeVisible();
    await expect(page.getByRole("heading", { level: 1, name: /Welcome/ })).toHaveCount(0);
    expect(delayedNavigations.count()).toBeGreaterThan(0);
    await expect(page.locator('[role="progressbar"], .animate-spin')).toHaveCount(0);
    await expect(page.getByRole("heading", { level: 1, name: /Welcome/ })).toBeVisible();
  });
});
