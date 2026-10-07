// @vitest-environment node
import { NextRequest } from "next/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { ACTIVITY_COOKIE_NAME, IDLE_TIMEOUT_MS } from "@core/data/auth.data";

import { config, proxy } from "./proxy";

const mocks = vi.hoisted(() => ({
  getState: vi.fn(),
  signOut: vi.fn(),
  setAll: undefined as undefined | ((cookies: unknown[], headers: Record<string, string>) => void),
}));

vi.mock("@lbc/providers", () => ({
  createSupabaseAuth: (options: { cookieStore: { setAll: typeof mocks.setAll } }) => {
    mocks.setAll = options.cookieStore.setAll;
    return { getState: mocks.getState, signOut: mocks.signOut };
  },
}));

const SIGNED_IN = {
  status: "signed_in",
  userId: "u1",
  email: "a@b.c",
  currentLevel: "aal1",
  nextLevel: "aal1",
  verifiedFactorId: null,
  accessToken: "t",
};

function requestFor(path: string, activityMs?: number) {
  const headers = new Headers();
  if (activityMs !== undefined) {
    headers.set("cookie", `${ACTIVITY_COOKIE_NAME}=${String(activityMs)}`);
  }
  return new NextRequest(`http://localhost:3000${path}`, { headers });
}

beforeEach(() => {
  vi.clearAllMocks();
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "http://127.0.0.1:54321");
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", "anon");
  mocks.signOut.mockResolvedValue({ ok: true, data: undefined });
});

describe("proxy", () => {
  it("should redirect a visitor without a session to the login page", async () => {
    mocks.getState.mockResolvedValue({ status: "signed_out" });

    const response = await proxy(requestFor("/"));

    expect(response.status).toBe(307);
    expect(new URL(response.headers.get("location") ?? "").pathname).toBe("/login");
    expect(response.headers.get("Cache-Control")).toBe("private, no-store");
  });

  it("should let a visitor without a session open the login page", async () => {
    mocks.getState.mockResolvedValue({ status: "signed_out" });

    const response = await proxy(requestFor("/login"));

    expect(response.headers.get("location")).toBeNull();
    expect(response.headers.get("x-middleware-next")).toBe("1");
  });

  it("should let an active session through and refresh the activity cookie", async () => {
    mocks.getState.mockResolvedValue(SIGNED_IN);

    const response = await proxy(requestFor("/", Date.now() - 1000));

    expect(response.headers.get("x-middleware-next")).toBe("1");
    const activityCookie = response.cookies.get(ACTIVITY_COOKIE_NAME);
    expect(Number(activityCookie?.value)).toBeGreaterThan(Date.now() - 5000);
  });

  it("should send a user who still owes a code back to the login page", async () => {
    mocks.getState.mockResolvedValue({ ...SIGNED_IN, nextLevel: "aal2" });

    const response = await proxy(requestFor("/", Date.now()));

    expect(new URL(response.headers.get("location") ?? "").pathname).toBe("/login");
  });

  it("should sign out and explain after 30 minutes without activity", async () => {
    mocks.getState.mockResolvedValue(SIGNED_IN);

    const response = await proxy(requestFor("/", Date.now() - IDLE_TIMEOUT_MS - 1000));

    const location = new URL(response.headers.get("location") ?? "");
    expect(location.pathname).toBe("/login");
    expect(location.searchParams.get("reason")).toBe("idle");
    expect(mocks.signOut).toHaveBeenCalledTimes(1);
    expect(response.cookies.get(ACTIVITY_COOKIE_NAME)?.value).toBe("");
  });

  it("should treat a signed in request without an activity cookie as idle", async () => {
    mocks.getState.mockResolvedValue(SIGNED_IN);

    const response = await proxy(requestFor("/"));

    expect(mocks.signOut).toHaveBeenCalledTimes(1);
    expect(response.status).toBe(307);
  });

  it("should write refreshed session cookies and cache headers onto the response", async () => {
    mocks.getState.mockImplementation(() => {
      mocks.setAll?.([{ name: "sb-token", value: "new", options: { httpOnly: true } }], {
        "Cache-Control": "no-store",
      });
      return Promise.resolve(SIGNED_IN);
    });

    const response = await proxy(requestFor("/", Date.now()));

    expect(response.cookies.get("sb-token")?.value).toBe("new");
  });

  it("should skip static files in its matcher", () => {
    expect(config.matcher[0]).toContain("_next/static");
  });
});
