import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { createSessionGraphqlClient } from "./session-client";

const mocks = vi.hoisted(() => ({ createGraphqlClient: vi.fn() }));

vi.mock("@config/graphql-client", () => ({ createGraphqlClient: mocks.createGraphqlClient }));

beforeEach(() => {
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "http://127.0.0.1:54321");
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", "anon-key");
});

afterEach(() => {
  vi.unstubAllEnvs();
  vi.clearAllMocks();
});

describe("createSessionGraphqlClient", () => {
  it("should build a client that sends the given access token", async () => {
    createSessionGraphqlClient("user-token");

    const options = mocks.createGraphqlClient.mock.calls[0]?.[0] as {
      supabaseUrl: string;
      anonKey: string;
      getAccessToken: () => Promise<string>;
    };
    expect(options.supabaseUrl).toBe("http://127.0.0.1:54321");
    expect(options.anonKey).toBe("anon-key");
    await expect(options.getAccessToken()).resolves.toBe("user-token");
  });

  it("should fail with the missing variable name when the environment is incomplete", () => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", "");

    expect(() => createSessionGraphqlClient("t")).toThrow("NEXT_PUBLIC_SUPABASE_ANON_KEY");
  });
});
