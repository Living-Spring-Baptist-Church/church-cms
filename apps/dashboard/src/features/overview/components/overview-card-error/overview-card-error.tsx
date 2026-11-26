import Link from "next/link";

import { Alert, Button } from "@lbc/ui";

import { OVERVIEW_COPY } from "@core/copy/overview.copy";
import { ROUTES } from "@core/data/routes.data";

type OverviewCardErrorProps = {
  /** The plain message of the AppError. Never the technical detail. */
  message: string;
};

/** Shown inside a card whose read failed, so the other cards still render. */
export function OverviewCardError({ message }: OverviewCardErrorProps) {
  return (
    <div className="flex flex-col gap-3">
      <Alert variant="destructive" role="alert">
        {message}
      </Alert>
      <Button asChild variant="outline" className="self-start">
        <Link href={ROUTES.home}>{OVERVIEW_COPY.retry}</Link>
      </Button>
    </div>
  );
}
