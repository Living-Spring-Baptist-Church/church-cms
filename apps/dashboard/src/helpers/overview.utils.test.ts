import { describe, expect, it } from "vitest";

import type { StaffRoleName } from "@core/auth/roles";
import { OVERVIEW_CARD_IDS } from "@core/data/overview.data";

import { isOverviewCardVisible, visibleQuickActions } from "./overview.utils";

function actionIdsFor(roles: readonly StaffRoleName[]): readonly string[] {
  return visibleQuickActions(roles).map((action) => action.id);
}

describe("isOverviewCardVisible", () => {
  it.each<StaffRoleName>(["super_admin", "pastor", "secretary", "usher"])(
    "should show last Sunday's attendance to %s",
    (role) => {
      expect(isOverviewCardVisible([role], OVERVIEW_CARD_IDS.lastSundayAttendance)).toBe(true);
    },
  );

  it.each<StaffRoleName>(["treasurer", "department_head", "content_editor"])(
    "should hide last Sunday's attendance from %s",
    (role) => {
      expect(isOverviewCardVisible([role], OVERVIEW_CARD_IDS.lastSundayAttendance)).toBe(false);
    },
  );

  it.each<StaffRoleName>(["super_admin", "pastor", "secretary"])(
    "should show new visitors this month to %s",
    (role) => {
      expect(isOverviewCardVisible([role], OVERVIEW_CARD_IDS.newVisitorsThisMonth)).toBe(true);
    },
  );

  it.each<StaffRoleName>(["usher", "treasurer", "department_head", "content_editor"])(
    "should hide new visitors this month from %s",
    (role) => {
      expect(isOverviewCardVisible([role], OVERVIEW_CARD_IDS.newVisitorsThisMonth)).toBe(false);
    },
  );

  it("should show new visitors this month when any held role allows it", () => {
    expect(
      isOverviewCardVisible(["usher", "secretary"], OVERVIEW_CARD_IDS.newVisitorsThisMonth),
    ).toBe(true);
  });

  it("should hide month-to-date giving from every role until finance has a data source", () => {
    expect(isOverviewCardVisible(["pastor"], OVERVIEW_CARD_IDS.monthToDateGiving)).toBe(false);
    expect(isOverviewCardVisible(["treasurer"], OVERVIEW_CARD_IDS.monthToDateGiving)).toBe(false);
  });
});

describe("visibleQuickActions", () => {
  it("should offer an usher the record attendance action", () => {
    expect(actionIdsFor(["usher"])).toEqual(["recordAttendance"]);
  });

  it("should offer a treasurer the record offering action", () => {
    expect(actionIdsFor(["treasurer"])).toEqual(["recordOffering"]);
  });

  it("should offer a secretary the attendance and add member actions", () => {
    expect(actionIdsFor(["secretary"])).toEqual(["recordAttendance", "addMember"]);
  });

  it("should offer a pastor no quick action, because the pastor only views", () => {
    expect(actionIdsFor(["pastor"])).toEqual([]);
  });

  it("should offer a department head no quick action", () => {
    expect(actionIdsFor(["department_head"])).toEqual([]);
  });
});
