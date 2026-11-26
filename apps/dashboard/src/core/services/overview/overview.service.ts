import { LastSundayAttendanceDocument } from "@lbc/db/dashboard";
import type { Client } from "@urql/core";

import { logger } from "@config/logger";
import { runQuery } from "@config/graphql-client";
import type { StaffRoleName } from "@core/auth/roles";
import { OVERVIEW_CARD_IDS } from "@core/data/overview.data";
import type { Result } from "@core/errors/app-error";
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
    logger.error("Could not load last Sunday's attendance", {
      code: result.error.code,
      detail: result.error.technicalDetail,
    });
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

export type LoadOverviewOptions = {
  readonly client: Client;
  readonly roles: readonly StaffRoleName[];
  readonly asOf: Date;
};

/** Reads only the cards the roles may see. A card the role may not see is never queried. */
export async function loadOverview(options: LoadOverviewOptions): Promise<OverviewData> {
  const { client, roles, asOf } = options;
  const canSeeAttendance = isOverviewCardVisible(roles, OVERVIEW_CARD_IDS.lastSundayAttendance);
  return {
    lastSundayAttendance: canSeeAttendance ? await fetchLastSundayAttendance(client, asOf) : null,
  };
}
