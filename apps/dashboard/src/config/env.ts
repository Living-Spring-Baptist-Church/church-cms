const SUPABASE_URL_VARIABLE = "NEXT_PUBLIC_SUPABASE_URL";
const SUPABASE_ANON_KEY_VARIABLE = "NEXT_PUBLIC_SUPABASE_ANON_KEY";

export type PublicEnv = {
  readonly supabaseUrl: string;
  readonly supabaseAnonKey: string;
};

function requireVariable(
  variableName: string,
  source: Readonly<Record<string, string | undefined>>,
) {
  const variableValue = source[variableName];
  if (!variableValue) {
    throw new Error(`Missing environment variable ${variableName}. See .env.example.`);
  }
  return variableValue;
}

export function readPublicEnv(source: Readonly<Record<string, string | undefined>>): PublicEnv {
  return {
    supabaseUrl: requireVariable(SUPABASE_URL_VARIABLE, source),
    supabaseAnonKey: requireVariable(SUPABASE_ANON_KEY_VARIABLE, source),
  };
}
