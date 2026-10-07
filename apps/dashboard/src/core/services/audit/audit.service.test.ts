import type { Client } from "@urql/core";
import { describe, expect, it, vi } from "vitest";

import { createAppError } from "@core/errors/app-error";

import { recordLogin } from "./audit.service";

const runMutation = vi.hoisted(() => vi.fn());

vi.mock("@config/graphql-client", () => ({ runMutation }));

const CLIENT = {} as Client;

describe("recordLogin", () => {
  it("should log a LOGIN for the staff member with the method and no personal data", async () => {
    runMutation.mockResolvedValue({ ok: true, data: { logAuditEvent: "id" } });

    const result = await recordLogin({ client: CLIENT, staffId: "s1", method: "password+totp" });

    expect(result).toEqual({ ok: true, data: undefined });
    expect(runMutation).toHaveBeenCalledWith(
      expect.objectContaining({
        variables: {
          action: "LOGIN",
          tableName: "staff",
          recordId: "s1",
          details: JSON.stringify({ method: "password+totp" }),
        },
      }),
    );
  });

  it("should pass a failure on", async () => {
    const error = createAppError("forbidden", "AUTH_FORBIDDEN");
    runMutation.mockResolvedValue({ ok: false, error });

    await expect(
      recordLogin({ client: CLIENT, staffId: "s1", method: "password" }),
    ).resolves.toEqual({ ok: false, error });
  });
});
