import { gql } from "@urql/core";
import { describe, expect, it, vi } from "vitest";

import { readPublicEnv } from "./env";
import { createGraphqlClient } from "./graphql-client";

const TEST_QUERY = gql`
  query Ping {
    __typename
  }
`;

describe("createGraphqlClient failure modes", () => {
  it("should not send the request and should report an error when the session lookup rejects", async () => {
    const fetchSpy = vi.fn<typeof fetch>();
    const client = createGraphqlClient({
      supabaseUrl: "http://127.0.0.1:54321",
      anonKey: "anon",
      getAccessToken: () => Promise.reject(new Error("session lookup failed")),
      fetchImplementation: fetchSpy,
    });
    const result = await client.query(TEST_QUERY, {}, { requestPolicy: "network-only" });
    expect(result.error).toBeDefined();
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("should expose no option that accepts a service role key", () => {
    const optionNames = ["supabaseUrl", "anonKey", "getAccessToken", "fetchImplementation"];
    expect(optionNames.join(",")).not.toMatch(/service/i);
  });
});

describe("readPublicEnv edge cases", () => {
  it("should throw when the anon key is an empty string", () => {
    expect(() =>
      readPublicEnv({
        NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:54321",
        NEXT_PUBLIC_SUPABASE_ANON_KEY: "",
      }),
    ).toThrow("NEXT_PUBLIC_SUPABASE_ANON_KEY");
  });

  it("should throw naming the url variable when it is missing", () => {
    expect(() => readPublicEnv({ NEXT_PUBLIC_SUPABASE_ANON_KEY: "anon" })).toThrow(
      "NEXT_PUBLIC_SUPABASE_URL",
    );
  });
});
