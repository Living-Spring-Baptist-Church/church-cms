import Link from "next/link";

import { Alert, Button, Card, CardContent, CardHeader, CardTitle, EmptyState } from "@lbc/ui";

import { OVERVIEW_COPY } from "@core/copy/overview.copy";
import { ROUTES } from "@core/data/routes.data";
import type { Result } from "@core/errors/app-error";
import type { AttendanceHeadcount, LastSundayAttendance } from "@core/types/overview.types";
import { formatServiceDateTime } from "@helpers/date.utils";

type HeadcountField = {
  readonly key: keyof AttendanceHeadcount;
  readonly label: string;
};

const HEADCOUNT_FIELDS: readonly HeadcountField[] = [
  { key: "men", label: OVERVIEW_COPY.lastSundayAttendance.men },
  { key: "women", label: OVERVIEW_COPY.lastSundayAttendance.women },
  { key: "children", label: OVERVIEW_COPY.lastSundayAttendance.children },
  { key: "visitors", label: OVERVIEW_COPY.lastSundayAttendance.visitors },
];

type LastSundayAttendanceCardProps = {
  result: Result<LastSundayAttendance | null>;
};

function ServiceLine({ service }: { readonly service: LastSundayAttendance }) {
  return (
    <div className="flex flex-col gap-1 text-sm">
      <p className="font-medium text-foreground">{service.serviceName}</p>
      <p className="text-muted-foreground">{formatServiceDateTime(service.startsAt)}</p>
    </div>
  );
}

function AttendanceBody({ result }: LastSundayAttendanceCardProps) {
  if (!result.ok) {
    return (
      <div className="flex flex-col gap-3">
        <Alert variant="destructive" role="alert">
          {result.error.message}
        </Alert>
        <Button asChild variant="outline" className="self-start">
          <Link href={ROUTES.home}>{OVERVIEW_COPY.retry}</Link>
        </Button>
      </div>
    );
  }
  const service = result.data;
  if (service === null) {
    return <EmptyState message={OVERVIEW_COPY.lastSundayAttendance.noService} />;
  }
  if (service.headcount === null) {
    return (
      <div className="flex flex-col gap-3">
        <ServiceLine service={service} />
        <EmptyState message={OVERVIEW_COPY.lastSundayAttendance.noCounts} />
      </div>
    );
  }
  const { headcount } = service;
  return (
    <div className="flex flex-col gap-4">
      <ServiceLine service={service} />
      <dl className="grid grid-cols-2 gap-4 sm:grid-cols-4">
        {HEADCOUNT_FIELDS.map((field) => (
          <div key={field.key} className="flex flex-col gap-1">
            <dt className="text-sm text-muted-foreground">{field.label}</dt>
            <dd className="text-2xl font-semibold text-primary">{headcount[field.key]}</dd>
          </div>
        ))}
      </dl>
    </div>
  );
}

/** The headcount of the latest Sunday service (OVR-01). Each state has its own plain message. */
export function LastSundayAttendanceCard({ result }: LastSundayAttendanceCardProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle as="h2">{OVERVIEW_COPY.lastSundayAttendance.title}</CardTitle>
      </CardHeader>
      <CardContent>
        <AttendanceBody result={result} />
      </CardContent>
    </Card>
  );
}
