import { LogAuditEventDocument } from "@lbc/db/dashboard";
import type { Client } from "@urql/core";

import { runMutation } from "@config/graphql-client";
import { LOGIN_AUDIT_ACTION, LOGIN_AUDIT_TABLE, type LoginMethod } from "@core/data/auth.data";
import type { Result } from "@core/errors/app-error";

export type RecordLoginOptions = {
  readonly client: Client;
  readonly staffId: string;
  readonly method: LoginMethod;
};

/** Writes a LOGIN row to the audit log as the signed-in user (AUD-01). Never put personal data in the details. */
export async function recordLogin(options: RecordLoginOptions): Promise<Result<undefined>> {
  const result = await runMutation({
    client: options.client,
    document: LogAuditEventDocument,
    variables: {
      action: LOGIN_AUDIT_ACTION,
      tableName: LOGIN_AUDIT_TABLE,
      recordId: options.staffId,
      // pg_graphql carries the JSON scalar as a serialized string.
      details: JSON.stringify({ method: options.method }),
    },
  });
  return result.ok ? { ok: true, data: undefined } : result;
}
