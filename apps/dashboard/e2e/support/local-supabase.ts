import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

// LOCAL ONLY. The end to end run signs in as the seeded @demo.church staff, so it needs the local stack
// (`pnpm db:start`, `pnpm db:reset`). It never talks to a hosted project.
const REPOSITORY_ROOT = fileURLToPath(new URL("../../../../", import.meta.url));
const SUPABASE_CONFIG_FILE = `${REPOSITORY_ROOT}supabase/config.toml`;
const SAFE_PROJECT_ID_PATTERN = /^[A-Za-z0-9_-]+$/;
const SUPABASE_CLI = `${REPOSITORY_ROOT}packages/db/node_modules/.bin/supabase`;

export const LOCAL_SUPABASE_URL_VARIABLE = "NEXT_PUBLIC_SUPABASE_URL";
export const LOCAL_SUPABASE_ANON_KEY_VARIABLE = "NEXT_PUBLIC_SUPABASE_ANON_KEY";

export type LocalSupabaseEnv = {
  readonly supabaseUrl: string;
  readonly supabaseAnonKey: string;
};

function readStatusValue(statusOutput: string, name: string): string | undefined {
  return new RegExp(`^${name}="([^"]+)"`, "m").exec(statusOutput)?.[1];
}

/** Uses the variables when set, otherwise asks the pinned Supabase CLI for the local values. */
export function readLocalSupabaseEnv(): LocalSupabaseEnv {
  const supabaseUrl = process.env[LOCAL_SUPABASE_URL_VARIABLE];
  const supabaseAnonKey = process.env[LOCAL_SUPABASE_ANON_KEY_VARIABLE];
  if (supabaseUrl && supabaseAnonKey) {
    return { supabaseUrl, supabaseAnonKey };
  }
  const statusOutput = execFileSync(SUPABASE_CLI, ["status", "-o", "env", "--workdir", "."], {
    cwd: REPOSITORY_ROOT,
    encoding: "utf8",
    shell: process.platform === "win32",
  });
  const apiUrl = readStatusValue(statusOutput, "API_URL");
  const anonKey = readStatusValue(statusOutput, "ANON_KEY");
  if (!apiUrl || !anonKey) {
    throw new Error("The local Supabase stack is not running. Run `pnpm db:start` first.");
  }
  return { supabaseUrl: apiUrl, supabaseAnonKey: anonKey };
}

function readLocalDatabaseContainer(): string {
  const match = /^project_id\s*=\s*"([^"]+)"/m.exec(readFileSync(SUPABASE_CONFIG_FILE, "utf8"));
  const projectId = match?.[1];
  if (!projectId || !SAFE_PROJECT_ID_PATTERN.test(projectId)) {
    throw new Error("No usable project_id in supabase/config.toml");
  }
  return `supabase_db_${projectId}`;
}

function runLocalSql(sql: string): void {
  execFileSync(
    "docker",
    ["exec", "-i", readLocalDatabaseContainer(), "psql", "-U", "postgres", "-d", "postgres"],
    { input: sql, stdio: ["pipe", "ignore", "inherit"] },
  );
}

/**
 * Gives the demo staff the public dev password (scripts/seed-local-auth.mjs) and removes their
 * authenticator factors, so pastor and super admin enrol afresh and the run knows the setup key.
 */
export function prepareLocalDemoStaff(): void {
  execFileSync("node", ["scripts/seed-local-auth.mjs"], { cwd: REPOSITORY_ROOT, stdio: "ignore" });
  runLocalSql(
    "delete from auth.mfa_factors where user_id in (select id from auth.users where email like '%@demo.church');",
  );
}
