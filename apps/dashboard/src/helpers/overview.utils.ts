import { filterByRoles, hasRole, type StaffRoleName } from "@core/auth/roles";
import { OVERVIEW_CARDS, QUICK_ACTIONS, type OverviewCardId } from "@core/data/overview.data";

/** True when the role may see the card and the card has a data source. Checked before any read. */
export function isOverviewCardVisible(
  heldRoles: readonly StaffRoleName[],
  cardId: OverviewCardId,
): boolean {
  return OVERVIEW_CARDS.some(
    (card) => card.id === cardId && card.isAvailable && hasRole(heldRoles, card.allowedRoles),
  );
}

export function visibleQuickActions(heldRoles: readonly StaffRoleName[]) {
  return filterByRoles(QUICK_ACTIONS, heldRoles);
}
