import { expect, test } from "@playwright/test";

import {
  CHURCH_NAME,
  expectNoAxeViolations,
  hasHorizontalOverflow,
  isMobileProject,
  readVisibleCardTitles,
  readVisibleModules,
  readVisibleQuickActions,
  revealMainNavigation,
} from "./support/overview-page";
import { ROLE_EXPECTATIONS } from "./support/role-expectations";
import { authStatePath, SEED_STAFF, SEED_STAFF_KEYS } from "./support/seed-staff";

for (const staffKey of SEED_STAFF_KEYS) {
  const expectation = ROLE_EXPECTATIONS[staffKey];
  const staff = SEED_STAFF[staffKey];

  test.describe(`overview as ${staffKey}`, () => {
    test.use({ storageState: authStatePath(staffKey) });

    test.beforeEach(async ({ page }) => {
      await page.goto("/");
      await expect(
        page.getByRole("heading", { level: 1, name: `Welcome, ${staff.fullName}` }),
      ).toBeVisible();
    });

    test("should show the church name and the user menu when the overview loads", async ({
      page,
    }, testInfo) => {
      const banner = page.getByRole("banner");
      await expect(banner.getByText(CHURCH_NAME, { exact: true })).toBeVisible();
      const accountNavigation = page.getByRole("navigation", { name: "Account" });
      await expect(accountNavigation.getByRole("button", { name: "Sign out" })).toBeVisible();
      const accountLink = accountNavigation.getByRole("link", { name: staff.fullName });
      if (isMobileProject(testInfo)) {
        await expect(accountLink).toBeHidden();
      } else {
        await expect(accountLink).toBeVisible();
        await expect(accountLink).toHaveAttribute("href", "/account/security");
      }
      await expect(
        page.getByRole("listitem").filter({ hasText: expectation.roleLabel }),
      ).toBeVisible();
    });

    test("should list only the modules the role may use when the navigation is opened", async ({
      page,
    }, testInfo) => {
      const navigation = await revealMainNavigation(page, testInfo);
      expect(await readVisibleModules(navigation)).toEqual(expectation.modules);
      await expect(navigation.getByRole("link", { name: "Overview" })).toHaveAttribute(
        "aria-current",
        "page",
      );
    });

    test("should show only the role's cards and never a giving figure when the overview loads", async ({
      page,
    }) => {
      expect(await readVisibleCardTitles(page)).toEqual(expectation.cards);
      await expect(page.getByRole("alert").filter({ hasText: /\S/ })).toHaveCount(0);
      await expect(page.getByText(/giving/i)).toHaveCount(0);
      await expect(page.getByText(/GH₵|GHS|cedi/i)).toHaveCount(0);
      if (expectation.cards.length === 0) {
        await expect(page.getByText("No figures are shown for your roles yet.")).toBeVisible();
      }
    });

    test("should offer only the role's quick actions when the overview loads", async ({ page }) => {
      expect(await readVisibleQuickActions(page)).toEqual(expectation.quickActions);
      const quickActionsHeading = page.getByRole("heading", { level: 2, name: "Quick actions" });
      if (expectation.quickActions.length === 0) {
        await expect(quickActionsHeading).toHaveCount(0);
        return;
      }
      await expect(quickActionsHeading).toBeVisible();
      for (const actionLabel of expectation.quickActions) {
        const action = page.getByRole("button", { name: actionLabel });
        await expect(action).toBeDisabled();
        await expect(action).toHaveAccessibleDescription("Not available yet");
      }
    });

    test("should have no axe violations when the overview loads", async ({ page }, testInfo) => {
      await expectNoAxeViolations(page);
      await revealMainNavigation(page, testInfo);
      await expectNoAxeViolations(page);
    });

    test("should not scroll sideways when the overview loads", async ({ page }) => {
      expect(await hasHorizontalOverflow(page)).toBe(false);
    });
  });
}
