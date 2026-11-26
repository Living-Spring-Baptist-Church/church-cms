import { LastSundayAttendanceDocument, NewVisitorsThisMonthDocument } from "@lbc/db/dashboard";
import type { Client } from "@urql/core";

import { logger } from "@config/logger";
import { runQuery } from "@config/graphql-client";
import type { StaffRoleName } from "@core/auth/roles";
import { OVERVIEW_CARD_IDS } from "@core/data/overview.data";
import { createAppError, type AppError, type Result } from "@core/errors/app-error";
import type {
  AttendanceHeadcount,
  LastSundayAttendance,
  OverviewData,
} from "@core/types/overview.types";
import { isOverviewCardVisible } from "@helpers/overview.utils";

type AttendanceCountRow = {
  readonly men: number;
  readonly women: number;
  readonly children: number;
  readonly visitors: number;
} | null;

const ATTENDANCE_FAILURE_LOG = "Could not load last Sunday's attendance";
const NEW_VISITORS_FAILURE_LOG = "Could not load new visitors this month";

function logReadFailure(message: string, error: AppError): void {
  logger.error(message, { code: error.code, detail: error.technicalDetail });
}

function toHeadcount(row: AttendanceCountRow): AttendanceHeadcount | null {
  if (row === null) {
    return null;
  }
  return { men: row.men, women: row.women, children: row.children, visitors: row.visitors };
}

/**
 * Reads the latest Sunday service on or before `asOf`. Data is null when no Sunday service exists
 * yet, and its headcount is null when no counts were recorded for that service.
 */
export async function fetchLastSundayAttendance(
  client: Client,
  asOf: Date,
): Promise<Result<LastSundayAttendance | null>> {
  const result = await runQuery({
    client,
    document: LastSundayAttendanceDocument,
    variables: { asOf: asOf.toISOString() },
  });
  if (!result.ok) {
    logReadFailure(ATTENDANCE_FAILURE_LOG, result.error);
    return result;
  }
  const service = result.data.servicesCollection.edges.at(0)?.node;
  if (service === undefined) {
    return { ok: true, data: null };
  }
  return {
    ok: true,
    data: {
      serviceName: service.name,
      startsAt: service.startsAt,
      headcount: toHeadcount(service.attendanceCount),
    },
  };
}

/** Reads the count of first visits this month. The database refuses roles that may not see it. */
export async function fetchNewVisitorsThisMonth(client: Client): Promise<Result<number>> {
  const result = await runQuery({ client, document: NewVisitorsThisMonthDocument, variables: {} });
  if (!result.ok) {
    logReadFailure(NEW_VISITORS_FAILURE_LOG, result.error);
    return result;
  }
  const visitorCount = result.data.getNewVisitorsThisMonth;
  if (visitorCount === null) {
    // A count is never null for a permitted role, so null means the API broke its contract.
    const error = createAppError("server", "getNewVisitorsThisMonth returned null");
    logReadFailure(NEW_VISITORS_FAILURE_LOG, error);
    return { ok: false, error };
  }
  return { ok: true, data: visitorCount };
}

export type LoadOverviewOptions = {
  readonly client: Client;
  readonly roles: readonly StaffRoleName[];
  readonly asOf: Date;
};

/** Reads only the cards the roles may see, in parallel. A card the role may not see is never queried. */
export async function loadOverview(options: LoadOverviewOptions): Promise<OverviewData> {
  const { client, roles, asOf } = options;
  const canSeeAttendance = isOverviewCardVisible(roles, OVERVIEW_CARD_IDS.lastSundayAttendance);
  const canSeeNewVisitors = isOverviewCardVisible(roles, OVERVIEW_CARD_IDS.newVisitorsThisMonth);
  const [lastSundayAttendance, newVisitorsThisMonth] = await Promise.all([
    canSeeAttendance ? fetchLastSundayAttendance(client, asOf) : null,
    canSeeNewVisitors ? fetchNewVisitorsThisMonth(client) : null,
  ]);
  return { lastSundayAttendance, newVisitorsThisMonth };
}
