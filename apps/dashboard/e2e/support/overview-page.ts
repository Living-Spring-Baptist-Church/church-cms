import AxeBuilder from "@axe-core/playwright";
import { expect, type Locator, type Page, type TestInfo } from "@playwright/test";

import { ALL_CARDS, ALL_QUICK_ACTIONS } from "./role-expectations";

export const CHURCH_NAME = "Living Spring Baptist Church";
const WCAG_TAGS = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"];
const MOBILE_PROJECT_NAME = "mobile-375";
const NOT_AVAILABLE_NOTE = "Not available yet";
// More than every focusable element before the main navigation (skip link, home link, account links).
const MAX_TAB_PRESSES = 10;

export function isMobileProject(testInfo: TestInfo): boolean {
  return testInfo.project.name === MOBILE_PROJECT_NAME;
}

export function mainNavigation(page: Page): Locator {
  return page.getByRole("navigation", { name: "Main" });
}

/** Opens the phone menu when the viewport hides the module row. */
export async function revealMainNavigation(page: Page, testInfo: TestInfo): Promise<Locator> {
  const navigation = mainNavigation(page);
  if (isMobileProject(testInfo)) {
    const menuToggle = navigation.getByText("Menu", { exact: true });
    await expect(menuToggle).toBeVisible();
    await menuToggle.click();
  }
  return navigation;
}

/** The module names in the visible navigation list, without the "Not available yet" note. */
export async function readVisibleModules(navigation: Locator): Promise<string[]> {
  const visibleList = navigation.locator("ul").filter({ visible: true });
  await expect(visibleList).toHaveCount(1);
  const itemTexts = await visibleList.locator(":scope > li").allInnerTexts();
  return itemTexts.map((itemText) => itemText.replace(NOT_AVAILABLE_NOTE, "").trim());
}

export async function readVisibleCardTitles(page: Page): Promise<string[]> {
  const headings = await page.getByRole("heading", { level: 2 }).allInnerTexts();
  return headings.filter((heading) => (ALL_CARDS as readonly string[]).includes(heading));
}

export async function readVisibleQuickActions(page: Page): Promise<string[]> {
  const labels = await page.getByRole("button").allInnerTexts();
  return labels
    .map((label) => label.trim())
    .filter((label) => (ALL_QUICK_ACTIONS as readonly string[]).includes(label));
}

/** Runs axe for WCAG 2.1 AA and fails with the rule ids and targets when anything is found. */
export async function expectNoAxeViolations(page: Page): Promise<void> {
  const results = await new AxeBuilder({ page }).withTags(WCAG_TAGS).analyze();
  const summary = results.violations.map((violation) => ({
    rule: violation.id,
    targets: violation.nodes.map((node) => node.target.join(" ")),
  }));
  expect(summary).toEqual([]);
}

/** True when nothing on the page is wider than the viewport (no sideways scroll on a phone). */
export async function hasHorizontalOverflow(page: Page): Promise<boolean> {
  return page.evaluate(
    () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
  );
}

/** Presses Tab like a keyboard user until `target` has focus, then asserts it does. */
export async function tabUntilFocused(page: Page, target: Locator): Promise<void> {
  for (let tabPress = 0; tabPress < MAX_TAB_PRESSES; tabPress += 1) {
    await page.keyboard.press("Tab");
    if (await target.evaluate((element) => element === document.activeElement)) {
      break;
    }
  }
  await expect(target).toBeFocused();
}

/** The focus ring is a box shadow (Tailwind ring utilities); "none" means no visible focus. */
export async function readFocusRing(target: Locator): Promise<string> {
  return target.evaluate((element) => getComputedStyle(element).boxShadow);
}
