import { CurrentStaffDocument } from "@lbc/db/dashboard";
import type { Client } from "@urql/core";

import { runQuery } from "@config/graphql-client";
import { isStaffRoleName } from "@core/auth/roles";
import type { Result } from "@core/errors/app-error";
import type { StaffProfile } from "@core/types/staff.types";

/**
 * Reads the signed-in user's own staff row. The database only returns it when the user may see it,
 * so a missing row (no staff record, or a deactivated account) comes back as null.
 */
export async function fetchStaffProfile(
  client: Client,
  staffId: string,
): Promise<Result<StaffProfile | null>> {
  const result = await runQuery({
    client,
    document: CurrentStaffDocument,
    variables: { staffId },
  });
  if (!result.ok) {
    return result;
  }
  const staffNode = result.data.staffCollection.edges.at(0)?.node;
  if (staffNode === undefined) {
    return { ok: true, data: null };
  }
  const roleNames = (staffNode.staffRolesCollection?.edges ?? []).map((edge) => edge.node.role);
  const knownRoles = roleNames.filter(isStaffRoleName);
  return {
    ok: true,
    data: {
      id: staffNode.id,
      fullName: staffNode.fullName,
      isActive: staffNode.isActive,
      roles: knownRoles,
      hasUnrecognisedRole: knownRoles.length < roleNames.length,
    },
  };
}
