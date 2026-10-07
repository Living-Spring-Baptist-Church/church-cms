import type { Client } from "@urql/core";

import { readPublicEnv } from "@config/env";
import { createGraphqlClient } from "@config/graphql-client";

/** A GraphQL client that acts as the signed-in user, so row level security applies. */
export function createSessionGraphqlClient(accessToken: string): Client {
  const { supabaseUrl, supabaseAnonKey } = readPublicEnv(process.env);
  return createGraphqlClient({
    supabaseUrl,
    anonKey: supabaseAnonKey,
    getAccessToken: () => Promise.resolve(accessToken),
  });
}
