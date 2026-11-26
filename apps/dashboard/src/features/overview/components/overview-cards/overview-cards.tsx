import type { ReactNode } from "react";

import { EmptyState } from "@lbc/ui";

import { OVERVIEW_COPY } from "@core/copy/overview.copy";
import { OVERVIEW_CARD_IDS, type OverviewCardId } from "@core/data/overview.data";
import type { OverviewData } from "@core/types/overview.types";
import { LastSundayAttendanceCard } from "@features/overview/components/last-sunday-attendance-card/last-sunday-attendance-card";
import { NewVisitorsThisMonthCard } from "@features/overview/components/new-visitors-this-month-card/new-visitors-this-month-card";

type OverviewCardsProps = {
  overview: OverviewData;
};

type VisibleCard = {
  readonly id: OverviewCardId;
  readonly card: ReactNode;
};

function collectVisibleCards({
  lastSundayAttendance,
  newVisitorsThisMonth,
}: OverviewData): readonly VisibleCard[] {
  const cards: VisibleCard[] = [];
  if (lastSundayAttendance !== null) {
    cards.push({
      id: OVERVIEW_CARD_IDS.lastSundayAttendance,
      card: <LastSundayAttendanceCard result={lastSundayAttendance} />,
    });
  }
  if (newVisitorsThisMonth !== null) {
    cards.push({
      id: OVERVIEW_CARD_IDS.newVisitorsThisMonth,
      card: <NewVisitorsThisMonthCard result={newVisitorsThisMonth} />,
    });
  }
  return cards;
}

/** Lists the cards the signed-in role may see. A null card was never read, so it is not rendered. */
export function OverviewCards({ overview }: OverviewCardsProps) {
  const visibleCards = collectVisibleCards(overview);
  if (visibleCards.length === 0) {
    return <EmptyState message={OVERVIEW_COPY.noCards} />;
  }
  return (
    <ul className="grid gap-6 md:grid-cols-2">
      {visibleCards.map(({ id, card }) => (
        <li key={id}>{card}</li>
      ))}
    </ul>
  );
}
