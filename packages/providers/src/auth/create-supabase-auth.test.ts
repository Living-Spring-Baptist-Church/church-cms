import { beforeEach, describe, expect, it, vi } from "vitest";

import type { AuthCookieStore } from "./auth.port";
import { createSupabaseAuth } from "./create-supabase-auth";

const createServerClient = vi.hoisted(() => vi.fn());

vi.mock("@supabase/ssr", () => ({ createServerClient }));

const SUPABASE_URL = "http://127.0.0.1:54321";
const ANON_KEY = "anon-key";

type CapturedConfig = {
  cookieOptions: Record<string, unknown>;
  cookies: {
    getAll: () => unknown;
    setAll: (cookies: unknown[], headers: Record<string, string>) => void;
  };
};

function createStore() {
  const setAll = vi.fn<AuthCookieStore["setAll"]>();
  const cookieStore: AuthCookieStore = { getAll: () => [{ name: "a", value: "1" }], setAll };
  return { cookieStore, setAll };
}

function captureConfig(): CapturedConfig {
  const calls = createServerClient.mock.calls as unknown as [string, string, CapturedConfig][];
  return (
    calls[calls.length - 1]?.[2] ?? {
      cookieOptions: {},
      cookies: { getAll: () => [], setAll: () => undefined },
    }
  );
}

describe("createSupabaseAuth", () => {
  beforeEach(() => {
    createServerClient.mockReset();
    createServerClient.mockReturnValue({ auth: {} });
  });

  it("should keep the session in httpOnly SameSite Lax cookies", () => {
    createSupabaseAuth({
      supabaseUrl: SUPABASE_URL,
      anonKey: ANON_KEY,
      cookieStore: createStore().cookieStore,
      totpIssuer: "Test Church",
      isSecureCookie: true,
    });

    expect(createServerClient).toHaveBeenCalledWith(SUPABASE_URL, ANON_KEY, expect.anything());
    expect(captureConfig().cookieOptions).toEqual({
      httpOnly: true,
      secure: true,
      sameSite: "lax",
      path: "/",
    });
  });

  it("should read cookies from the store and write them back with the cache headers", () => {
    const { cookieStore, setAll } = createStore();
    createSupabaseAuth({
      supabaseUrl: SUPABASE_URL,
      anonKey: ANON_KEY,
      cookieStore,
      totpIssuer: "Test Church",
      isSecureCookie: false,
    });
    const { cookies } = captureConfig();

    expect(cookies.getAll()).toEqual([{ name: "a", value: "1" }]);
    cookies.setAll([{ name: "sb", value: "token", options: { sameSite: "lax", maxAge: 5 } }], {
      "Cache-Control": "no-store",
    });

    expect(setAll).toHaveBeenCalledWith(
      [{ name: "sb", value: "token", options: { sameSite: "lax", maxAge: 5 } }],
      { "Cache-Control": "no-store" },
    );
  });

  it("should drop a SameSite value the port does not know", () => {
    const { cookieStore, setAll } = createStore();
    createSupabaseAuth({
      supabaseUrl: SUPABASE_URL,
      anonKey: ANON_KEY,
      cookieStore,
      totpIssuer: "Test Church",
      isSecureCookie: false,
    });

    captureConfig().cookies.setAll([{ name: "sb", value: "t", options: { sameSite: true } }], {});

    expect(setAll).toHaveBeenCalledWith(
      [{ name: "sb", value: "t", options: { sameSite: undefined } }],
      {},
    );
  });
});
