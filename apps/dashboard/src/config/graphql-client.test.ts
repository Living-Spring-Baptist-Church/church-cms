import { gql } from "@urql/core";
import { describe, expect, it, vi } from "vitest";

import { createGraphqlClient } from "./graphql-client";

const SUPABASE_URL = "http://127.0.0.1:54321";
const ANON_KEY = "test-anon-key";
const SESSION_TOKEN = "test-session-token";
const TEST_QUERY = gql`
  query Ping {
    __typename
  }
`;

function createFetchSpy() {
  return vi.fn<typeof fetch>(() =>
    Promise.resolve(
      new Response(JSON.stringify({ data: { __typename: "Query" } }), {
        headers: { "Content-Type": "application/json" },
      }),
    ),
  );
}

async function sendRequest(getAccessToken: () => Promise<string | undefined>) {
  const fetchSpy = createFetchSpy();
  const client = createGraphqlClient({
    supabaseUrl: SUPABASE_URL,
    anonKey: ANON_KEY,
    getAccessToken,
    fetchImplementation: fetchSpy,
  });
  await client.query(TEST_QUERY, {}, { requestPolicy: "network-only" });
  const [requestUrl, requestInit] = fetchSpy.mock.calls[0] ?? [];
  return { requestUrl, headers: new Headers(requestInit?.headers) };
}

describe("createGraphqlClient", () => {
  it("should call the pg_graphql endpoint of the project", async () => {
    const { requestUrl } = await sendRequest(() => Promise.resolve(SESSION_TOKEN));
    expect(requestUrl).toBe(`${SUPABASE_URL}/graphql/v1`);
  });

  it("should send the signed-in user's token as bearer and the anon key as apikey", async () => {
    const { headers } = await sendRequest(() => Promise.resolve(SESSION_TOKEN));
    expect(headers.get("Authorization")).toBe(`Bearer ${SESSION_TOKEN}`);
    expect(headers.get("apikey")).toBe(ANON_KEY);
  });

  it("should fall back to the anon key as bearer when nobody is signed in", async () => {
    const { headers } = await sendRequest(() => Promise.resolve(undefined));
    expect(headers.get("Authorization")).toBe(`Bearer ${ANON_KEY}`);
  });
});
