import type { Client } from "@urql/core";
import { describe, expect, it, vi } from "vitest";

import { createAppError } from "@core/errors/app-error";

import { fetchStaffProfile } from "./staff.service";

const runQuery = vi.hoisted(() => vi.fn());

vi.mock("@config/graphql-client", () => ({ runQuery }));

const CLIENT = {} as Client;

function staffResponse(nodes: readonly unknown[]) {
  return { ok: true, data: { staffCollection: { edges: nodes.map((node) => ({ node })) } } };
}

describe("fetchStaffProfile", () => {
  it("should map the staff row and keep only known role names", async () => {
    runQuery.mockResolvedValue(
      staffResponse([
        {
          id: "s1",
          fullName: "Demo Pastor",
          isActive: true,
          staffRolesCollection: {
            edges: [{ node: { role: "pastor" } }, { node: { role: "wizard" } }],
          },
        },
      ]),
    );

    await expect(fetchStaffProfile(CLIENT, "s1")).resolves.toEqual({
      ok: true,
      data: {
        id: "s1",
        fullName: "Demo Pastor",
        isActive: true,
        roles: ["pastor"],
        hasUnrecognisedRole: true,
      },
    });
    expect(runQuery).toHaveBeenCalledWith(
      expect.objectContaining({ variables: { staffId: "s1" } }),
    );
  });

  it("should return null when the database shows no staff row", async () => {
    runQuery.mockResolvedValue(staffResponse([]));

    await expect(fetchStaffProfile(CLIENT, "s1")).resolves.toEqual({ ok: true, data: null });
  });

  it("should treat a missing role collection as no roles", async () => {
    runQuery.mockResolvedValue(
      staffResponse([{ id: "s1", fullName: "A", isActive: false, staffRolesCollection: null }]),
    );

    await expect(fetchStaffProfile(CLIENT, "s1")).resolves.toMatchObject({
      data: { roles: [], isActive: false, hasUnrecognisedRole: false },
    });
  });

  it("should pass a failed query on", async () => {
    const error = createAppError("network", "down");
    runQuery.mockResolvedValue({ ok: false, error });

    await expect(fetchStaffProfile(CLIENT, "s1")).resolves.toEqual({ ok: false, error });
  });
});
