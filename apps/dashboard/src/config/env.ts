import { z } from "zod";

const SUPABASE_URL_VARIABLE = "NEXT_PUBLIC_SUPABASE_URL";
const SUPABASE_ANON_KEY_VARIABLE = "NEXT_PUBLIC_SUPABASE_ANON_KEY";

const publicEnvSchema = z.object({
  [SUPABASE_URL_VARIABLE]: z.url({
    error: `Missing or invalid environment variable ${SUPABASE_URL_VARIABLE}. See .env.example.`,
  }),
  [SUPABASE_ANON_KEY_VARIABLE]: z
    .string({
      error: `Missing environment variable ${SUPABASE_ANON_KEY_VARIABLE}. See .env.example.`,
    })
    .min(1, {
      error: `Missing environment variable ${SUPABASE_ANON_KEY_VARIABLE}. See .env.example.`,
    }),
});

export type PublicEnv = {
  readonly supabaseUrl: string;
  readonly supabaseAnonKey: string;
};

export function readPublicEnv(source: Readonly<Record<string, string | undefined>>): PublicEnv {
  const parsed = publicEnvSchema.safeParse(source);
  if (!parsed.success) {
    throw new Error(parsed.error.issues.map((issue) => issue.message).join(" "));
  }
  return {
    supabaseUrl: parsed.data[SUPABASE_URL_VARIABLE],
    supabaseAnonKey: parsed.data[SUPABASE_ANON_KEY_VARIABLE],
  };
}
