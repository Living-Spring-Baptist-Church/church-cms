import { Client, cacheExchange, fetchExchange } from "@urql/core";

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
