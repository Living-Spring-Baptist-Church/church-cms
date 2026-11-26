import { EmptyState } from "@lbc/ui";

import { OVERVIEW_COPY } from "@core/copy/overview.copy";
import type { OverviewData } from "@core/types/overview.types";
import { LastSundayAttendanceCard } from "@features/overview/components/last-sunday-attendance-card/last-sunday-attendance-card";

type OverviewCardsProps = {
  overview: OverviewData;
};

/** Lists the cards the signed-in role may see. A null card was never read, so it is not rendered. */
export function OverviewCards({ overview }: OverviewCardsProps) {
  const { lastSundayAttendance } = overview;
  if (lastSundayAttendance === null) {
    return <EmptyState message={OVERVIEW_COPY.noCards} />;
  }
  return (
    <ul className="grid gap-6 md:grid-cols-2">
      <li>
        <LastSundayAttendanceCard result={lastSundayAttendance} />
      </li>
    </ul>
  );
}
