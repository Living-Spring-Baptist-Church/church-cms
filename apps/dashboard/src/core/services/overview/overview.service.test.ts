import { beforeEach, describe, expect, it, vi } from "vitest";

import { createAppError } from "@core/errors/app-error";

import { fetchLastSundayAttendance, loadOverview } from "./overview.service";

const mocks = vi.hoisted(() => ({ runQuery: vi.fn(), error: vi.fn() }));

vi.mock("@config/graphql-client", () => ({ runQuery: mocks.runQuery }));
vi.mock("@config/logger", () => ({ logger: { error: mocks.error } }));

const CLIENT = {} as never;
const AS_OF = new Date("2026-10-27T12:00:00.000Z");

function serviceEdges(attendanceCount: unknown) {
  return {
    servicesCollection: {
      edges: [
        {
          node: {
            name: "Sunday First Service",
            startsAt: "2026-10-25T08:00:00+00:00",
            attendanceCount,
          },
        },
      ],
    },
  };
}

const RECORDED_COUNTS = { men: 40, women: 55, children: 18, visitors: 3 };

beforeEach(() => {
  vi.clearAllMocks();
});

describe("fetchLastSundayAttendance", () => {
  it("should ask for the latest service on or before the given time", async () => {
    mocks.runQuery.mockResolvedValue({ ok: true, data: { servicesCollection: { edges: [] } } });

    await fetchLastSundayAttendance(CLIENT, AS_OF);

    expect(mocks.runQuery).toHaveBeenCalledWith(
      expect.objectContaining({ variables: { asOf: "2026-10-27T12:00:00.000Z" } }),
    );
  });

  it("should return the headcount recorded for the last Sunday service", async () => {
    mocks.runQuery.mockResolvedValue({ ok: true, data: serviceEdges(RECORDED_COUNTS) });

    const result = await fetchLastSundayAttendance(CLIENT, AS_OF);

    expect(result).toEqual({
      ok: true,
      data: {
        serviceName: "Sunday First Service",
        startsAt: "2026-10-25T08:00:00+00:00",
        headcount: RECORDED_COUNTS,
      },
    });
  });

  it("should return a null headcount when no counts were recorded for the service", async () => {
    mocks.runQuery.mockResolvedValue({ ok: true, data: serviceEdges(null) });

    const result = await fetchLastSundayAttendance(CLIENT, AS_OF);

    expect(result).toMatchObject({ ok: true, data: { headcount: null } });
  });

  it("should return null data when no Sunday service exists yet", async () => {
    mocks.runQuery.mockResolvedValue({ ok: true, data: { servicesCollection: { edges: [] } } });

    await expect(fetchLastSundayAttendance(CLIENT, AS_OF)).resolves.toEqual({
      ok: true,
      data: null,
    });
  });

  it("should pass a failed read through as an error without any data", async () => {
    const failure = { ok: false, error: createAppError("network", "socket closed") };
    mocks.runQuery.mockResolvedValue(failure);

    await expect(fetchLastSundayAttendance(CLIENT, AS_OF)).resolves.toBe(failure);
  });

  it("should log the technical detail of a failed read", async () => {
    mocks.runQuery.mockResolvedValue({
      ok: false,
      error: createAppError("network", "socket closed"),
    });

    await fetchLastSundayAttendance(CLIENT, AS_OF);

    expect(mocks.error).toHaveBeenCalledWith(
      "Could not load last Sunday's attendance",
      expect.objectContaining({ code: "network", detail: "socket closed" }),
    );
  });
});

describe("loadOverview", () => {
  it("should read attendance for a role that may see the card", async () => {
    mocks.runQuery.mockResolvedValue({ ok: true, data: serviceEdges(RECORDED_COUNTS) });

    const overview = await loadOverview({ client: CLIENT, roles: ["usher"], asOf: AS_OF });

    expect(mocks.runQuery).toHaveBeenCalledTimes(1);
    expect(overview.lastSundayAttendance).toMatchObject({ ok: true });
  });

  it("should never query attendance for a role without the permission", async () => {
    const overview = await loadOverview({ client: CLIENT, roles: ["treasurer"], asOf: AS_OF });

    expect(mocks.runQuery).not.toHaveBeenCalled();
    expect(overview.lastSundayAttendance).toBeNull();
  });

  it("should never query attendance for a department head, whose view is limited to their department", async () => {
    const overview = await loadOverview({
      client: CLIENT,
      roles: ["department_head"],
      asOf: AS_OF,
    });

    expect(mocks.runQuery).not.toHaveBeenCalled();
    expect(overview.lastSundayAttendance).toBeNull();
  });
});
