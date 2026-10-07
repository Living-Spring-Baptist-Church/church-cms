import type { TypedDocumentNode } from "@graphql-typed-document-node/core";
import {
  Client,
  cacheExchange,
  fetchExchange,
  type AnyVariables,
  type CombinedError,
  type OperationResult,
} from "@urql/core";

import {
  createAppError,
  type AppError,
  type AppErrorCode,
  type Result,
} from "@core/errors/app-error";

const GRAPHQL_PATH = "/graphql/v1";
const API_KEY_HEADER = "apikey";
const AUTHORIZATION_HEADER = "Authorization";
const BEARER_PREFIX = "Bearer";

export type GetAccessToken = () => Promise<string | undefined>;

export type GraphqlClientOptions = {
  readonly supabaseUrl: string;
  readonly anonKey: string;
  /** Returns the signed-in user's session access token, or undefined when signed out. */
  readonly getAccessToken: GetAccessToken;
  readonly fetchImplementation?: typeof fetch;
};

/**
 * The one GraphQL client. Every request carries the anon key as `apikey` and the signed-in
 * user's access token as the bearer, so pg_graphql runs as that user and RLS applies.
 * The service role key is never accepted here (CLAUDE.md rule 8).
 */
export function createGraphqlClient(options: GraphqlClientOptions): Client {
  const { supabaseUrl, anonKey, getAccessToken, fetchImplementation = fetch } = options;

  const fetchWithSession: typeof fetch = async (input, init) => {
    const headers = new Headers(init?.headers);
    headers.set(API_KEY_HEADER, anonKey);
    const accessToken = await getAccessToken();
    headers.set(AUTHORIZATION_HEADER, `${BEARER_PREFIX} ${accessToken ?? anonKey}`);
    return fetchImplementation(input, { ...init, headers });
  };

  return new Client({
    url: `${supabaseUrl}${GRAPHQL_PATH}`,
    exchanges: [cacheExchange, fetchExchange],
    preferGetMethod: false,
    fetch: fetchWithSession,
  });
}

const HTTP_UNAUTHORIZED = 401;
const HTTP_FORBIDDEN = 403;

// Stable codes raised by the database functions (docs/standards/backend.md, error catalogue).
const BACKEND_CODE_TO_APP_CODE: Readonly<Record<string, AppErrorCode>> = {
  AUTH_FORBIDDEN: "forbidden",
  VALIDATION_FAILED: "validation",
  NOT_FOUND: "not_found",
};
const VALIDATION_CODE_PREFIXES: readonly string[] = ["STAFF_", "FINANCE_", "CONTENT_"];

function classifyHttpStatus(status: number | undefined): AppErrorCode {
  if (status === HTTP_UNAUTHORIZED) {
    return "unauthenticated";
  }
  return status === HTTP_FORBIDDEN ? "forbidden" : "network";
}

function classifyBackendCode(backendCode: string): AppErrorCode {
  const exactMatch = BACKEND_CODE_TO_APP_CODE[backendCode];
  if (exactMatch !== undefined) {
    return exactMatch;
  }
  const isRuleViolation = VALIDATION_CODE_PREFIXES.some((prefix) => backendCode.startsWith(prefix));
  return isRuleViolation ? "validation" : "server";
}

/**
 * The only place GraphQL failures are inspected. A response can be HTTP 200 and still carry an
 * `errors` array, so both transport failures and GraphQL errors end up as one typed AppError.
 */
export function classifyGraphqlError(error: CombinedError): AppError {
  if (error.networkError) {
    return createAppError(
      classifyHttpStatus((error.response as { status?: number } | undefined)?.status),
      error.networkError.message,
    );
  }
  const [firstError] = error.graphQLErrors;
  return createAppError(classifyBackendCode(firstError?.message ?? ""), error.message);
}

export type OperationOptions<TData, TVariables extends AnyVariables> = {
  readonly client: Client;
  readonly document: TypedDocumentNode<TData, TVariables>;
  readonly variables: TVariables;
};

function toResult<TData>(result: OperationResult<TData>): Result<TData> {
  if (result.error) {
    return { ok: false, error: classifyGraphqlError(result.error) };
  }
  if (result.data === undefined) {
    return { ok: false, error: createAppError("server", "The response had no data") };
  }
  return { ok: true, data: result.data };
}

/** Runs a query and returns data or a classified AppError. Never throws for a failed request. */
export async function runQuery<TData, TVariables extends AnyVariables>(
  options: OperationOptions<TData, TVariables>,
): Promise<Result<TData>> {
  const result = await options.client
    .query(options.document, options.variables, { requestPolicy: "network-only" })
    .toPromise();
  return toResult(result);
}

/** Runs a mutation and returns data or a classified AppError. Never throws for a failed request. */
export async function runMutation<TData, TVariables extends AnyVariables>(
  options: OperationOptions<TData, TVariables>,
): Promise<Result<TData>> {
  const result = await options.client.mutation(options.document, options.variables).toPromise();
  return toResult(result);
}
