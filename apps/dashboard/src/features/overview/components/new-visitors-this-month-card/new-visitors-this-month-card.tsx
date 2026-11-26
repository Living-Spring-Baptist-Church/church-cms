import { EmptyState } from "@lbc/ui";

import { OVERVIEW_COPY } from "@core/copy/overview.copy";
import type { Result } from "@core/errors/app-error";
import { OverviewCard } from "@features/overview/components/overview-card/overview-card";
import { OverviewCardError } from "@features/overview/components/overview-card-error/overview-card-error";

type NewVisitorsThisMonthCardProps = {
  result: Result<number>;
};

function NewVisitorsBody({ result }: NewVisitorsThisMonthCardProps) {
  if (!result.ok) {
    return <OverviewCardError message={result.error.message} />;
  }
  if (result.data === 0) {
    return <EmptyState message={OVERVIEW_COPY.newVisitorsThisMonth.noVisitors} />;
  }
  return (
    <dl className="flex flex-col gap-1">
      <dt className="text-sm text-muted-foreground">
        {OVERVIEW_COPY.newVisitorsThisMonth.countLabel}
      </dt>
      <dd className="text-2xl font-semibold text-primary">{result.data}</dd>
    </dl>
  );
}

/** First visits in the current calendar month, church time (OVR-01). */
export function NewVisitorsThisMonthCard({ result }: NewVisitorsThisMonthCardProps) {
  return (
    <OverviewCard title={OVERVIEW_COPY.newVisitorsThisMonth.title}>
      <NewVisitorsBody result={result} />
    </OverviewCard>
  );
}
