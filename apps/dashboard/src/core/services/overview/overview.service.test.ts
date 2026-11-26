import { LastSundayAttendanceDocument, NewVisitorsThisMonthDocument } from "@lbc/db/dashboard";
import { beforeEach, describe, expect, it, vi } from "vitest";

import type { StaffRoleName } from "@core/auth/roles";
import { createAppError } from "@core/errors/app-error";

import {
  fetchLastSundayAttendance,
  fetchNewVisitorsThisMonth,
  loadOverview,
} from "./overview.service";

type QueryOptions = { readonly document: unknown };

const mocks = vi.hoisted(() => ({
  runQuery: vi.fn<(options: QueryOptions) => Promise<unknown>>(),
  error: vi.fn(),
}));

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

describe("fetchNewVisitorsThisMonth", () => {
  it("should read the new visitors document", async () => {
    mocks.runQuery.mockResolvedValue({ ok: true, data: { getNewVisitorsThisMonth: 5 } });

    await fetchNewVisitorsThisMonth(CLIENT);

    expect(mocks.runQuery).toHaveBeenCalledWith(
      expect.objectContaining({ document: NewVisitorsThisMonthDocument }),
    );
  });

  it("should return the number of new visitors this month", async () => {
    mocks.runQuery.mockResolvedValue({ ok: true, data: { getNewVisitorsThisMonth: 5 } });

    await expect(fetchNewVisitorsThisMonth(CLIENT)).resolves.toEqual({ ok: true, data: 5 });
  });

  it("should return zero as a real count when no one visited for the first time", async () => {
    mocks.runQuery.mockResolvedValue({ ok: true, data: { getNewVisitorsThisMonth: 0 } });

    await expect(fetchNewVisitorsThisMonth(CLIENT)).resolves.toEqual({ ok: true, data: 0 });
  });

  it("should treat a null count as a server error and log it", async () => {
    mocks.runQuery.mockResolvedValue({ ok: true, data: { getNewVisitorsThisMonth: null } });

    const result = await fetchNewVisitorsThisMonth(CLIENT);

    expect(result).toMatchObject({ ok: false, error: { code: "server" } });
    expect(mocks.error).toHaveBeenCalledWith(
      "Could not load new visitors this month",
      expect.objectContaining({ code: "server" }),
    );
  });

  it("should pass a refused read through as an error and log its detail", async () => {
    const failure = { ok: false, error: createAppError("forbidden", "AUTH_FORBIDDEN") };
    mocks.runQuery.mockResolvedValue(failure);

    await expect(fetchNewVisitorsThisMonth(CLIENT)).resolves.toBe(failure);
    expect(mocks.error).toHaveBeenCalledWith(
      "Could not load new visitors this month",
      expect.objectContaining({ code: "forbidden", detail: "AUTH_FORBIDDEN" }),
    );
  });
});

function answerEachDocument(): void {
  mocks.runQuery.mockImplementation(({ document }) => {
    if (document === NewVisitorsThisMonthDocument) {
      return Promise.resolve({ ok: true, data: { getNewVisitorsThisMonth: 6 } });
    }
    return Promise.resolve({ ok: true, data: serviceEdges(RECORDED_COUNTS) });
  });
}

function queriedDocuments(): readonly unknown[] {
  return mocks.runQuery.mock.calls.map(([options]) => options.document);
}

describe("loadOverview", () => {
  it("should read attendance but never new visitors for an usher", async () => {
    answerEachDocument();

    const overview = await loadOverview({ client: CLIENT, roles: ["usher"], asOf: AS_OF });

    expect(queriedDocuments()).toEqual([LastSundayAttendanceDocument]);
    expect(overview.lastSundayAttendance).toMatchObject({ ok: true });
    expect(overview.newVisitorsThisMonth).toBeNull();
  });

  it.each<StaffRoleName>(["super_admin", "pastor", "secretary"])(
    "should read both cards for %s",
    async (role) => {
      answerEachDocument();

      const overview = await loadOverview({ client: CLIENT, roles: [role], asOf: AS_OF });

      expect(queriedDocuments()).toHaveLength(2);
      expect(queriedDocuments()).toContain(NewVisitorsThisMonthDocument);
      expect(overview.newVisitorsThisMonth).toEqual({ ok: true, data: 6 });
      expect(overview.lastSundayAttendance).toMatchObject({ ok: true });
    },
  );

  it.each<StaffRoleName>(["treasurer", "department_head", "content_editor"])(
    "should never query any card for %s, who may see neither",
    async (role) => {
      const overview = await loadOverview({ client: CLIENT, roles: [role], asOf: AS_OF });

      expect(mocks.runQuery).not.toHaveBeenCalled();
      expect(overview).toEqual({ lastSundayAttendance: null, newVisitorsThisMonth: null });
    },
  );

  it("should start both reads before either finishes", async () => {
    mocks.runQuery.mockReturnValue(new Promise(() => undefined));

    void loadOverview({ client: CLIENT, roles: ["pastor"], asOf: AS_OF });
    await Promise.resolve();

    expect(mocks.runQuery).toHaveBeenCalledTimes(2);
  });

  it("should still return attendance when the new visitors read fails", async () => {
    mocks.runQuery.mockImplementation(({ document }) =>
      Promise.resolve(
        document === NewVisitorsThisMonthDocument
          ? { ok: false, error: createAppError("network", "socket closed") }
          : { ok: true, data: serviceEdges(RECORDED_COUNTS) },
      ),
    );

    const overview = await loadOverview({ client: CLIENT, roles: ["secretary"], asOf: AS_OF });

    expect(overview.lastSundayAttendance).toMatchObject({ ok: true });
    expect(overview.newVisitorsThisMonth).toMatchObject({ ok: false, error: { code: "network" } });
  });
});
