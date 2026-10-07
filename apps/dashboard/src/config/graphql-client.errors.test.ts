import { gql } from "@urql/core";
import { describe, expect, it, vi } from "vitest";

import { createGraphqlClient, runMutation, runQuery } from "./graphql-client";

const QUERY = gql`
  query Ping {
    __typename
  }
`;
const MUTATION = gql`
  mutation Touch {
    __typename
  }
`;

function createClient(response: () => Response | Promise<Response>) {
  return createGraphqlClient({
    supabaseUrl: "http://127.0.0.1:54321",
    anonKey: "anon",
    getAccessToken: () => Promise.resolve("token"),
    fetchImplementation: vi.fn<typeof fetch>(() => Promise.resolve(response())),
  });
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function failureOf(response: () => Response | Promise<Response>) {
  const result = await runQuery({ client: createClient(response), document: QUERY, variables: {} });
  return result.ok ? null : result.error;
}

describe("runQuery", () => {
  it("should return the data of a successful response", async () => {
    const client = createClient(() => jsonResponse({ data: { __typename: "Query" } }));

    await expect(runQuery({ client, document: QUERY, variables: {} })).resolves.toEqual({
      ok: true,
      data: { __typename: "Query" },
    });
  });

  it.each([
    ["AUTH_FORBIDDEN", "forbidden"],
    ["VALIDATION_FAILED", "validation"],
    ["NOT_FOUND", "not_found"],
    ["STAFF_LAST_SUPER_ADMIN", "validation"],
    ["FINANCE_PERIOD_CLOSED", "validation"],
    ["SOMETHING_ELSE", "server"],
  ])(
    "should classify the backend code %s as %s even in an HTTP 200 response",
    async (code, expected) => {
      const error = await failureOf(() =>
        jsonResponse({ data: null, errors: [{ message: code }] }),
      );

      expect(error?.code).toBe(expected);
    },
  );

  it("should never show backend text to the user", async () => {
    const error = await failureOf(() =>
      jsonResponse({ data: null, errors: [{ message: "relation staff does not exist" }] }),
    );

    expect(error?.message).toBe("Something went wrong on our side. Try again in a moment.");
    expect(error?.technicalDetail).toContain("relation staff does not exist");
  });

  it.each([
    [401, "unauthenticated"],
    [403, "forbidden"],
    [502, "network"],
  ])("should classify HTTP %i as %s", async (status, expected) => {
    const error = await failureOf(() => jsonResponse({ message: "nope" }, status));

    expect(error?.code).toBe(expected);
  });

  it("should classify a failed connection as a network error", async () => {
    const error = await failureOf(() => Promise.reject(new Error("fetch failed")));

    expect(error?.code).toBe("network");
  });

  it("should treat a response with neither data nor errors as a network failure", async () => {
    const error = await failureOf(() => jsonResponse({}));

    expect(error?.code).toBe("network");
  });
});

describe("runMutation", () => {
  it("should return the data of a successful mutation", async () => {
    const client = createClient(() => jsonResponse({ data: { __typename: "Mutation" } }));

    await expect(runMutation({ client, document: MUTATION, variables: {} })).resolves.toEqual({
      ok: true,
      data: { __typename: "Mutation" },
    });
  });

  it("should return a classified error for a failed mutation", async () => {
    const client = createClient(() =>
      jsonResponse({ data: null, errors: [{ message: "AUTH_FORBIDDEN" }] }),
    );

    const result = await runMutation({ client, document: MUTATION, variables: {} });

    expect(result).toMatchObject({ ok: false, error: { code: "forbidden" } });
  });
});
