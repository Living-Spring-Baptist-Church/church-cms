// LOCAL DEVELOPMENT ONLY. Gives the seeded @demo.church staff a known, public password so that
// sign in can be tried on a laptop: `pnpm db:start`, `pnpm db:reset`, then `pnpm db:seed-local-auth`.
//
// It is deliberately not part of `supabase db reset` (config.toml sql_paths), because a seed that
// reaches a hosted project would publish a password for super-admin@demo.church. This script can
// only reach the local Supabase database container: it runs psql inside the Docker container named
// after the project_id in supabase/config.toml, and does nothing when that container is not running.
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const SUPABASE_CONFIG_FILE = "supabase/config.toml";
const SEED_FILE = "supabase/seed.local-auth.sql";
const DATABASE_USER = "postgres";
const DATABASE_NAME = "postgres";
const SAFE_PROJECT_ID_PATTERN = /^[A-Za-z0-9_-]+$/;

function readProjectId() {
  const match = /^project_id\s*=\s*"([^"]+)"/m.exec(readFileSync(SUPABASE_CONFIG_FILE, "utf8"));
  const projectId = match?.[1];
  if (!projectId || !SAFE_PROJECT_ID_PATTERN.test(projectId)) {
    throw new Error(`No usable project_id found in ${SUPABASE_CONFIG_FILE}`);
  }
  return projectId;
}

function assertLocalContainerRunning(containerName) {
  try {
    const isRunning = execFileSync(
      "docker",
      ["inspect", "--format", "{{.State.Running}}", containerName],
      { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
    ).trim();
    if (isRunning === "true") {
      return;
    }
  } catch {
    // Falls through to the message below.
  }
  throw new Error(
    `The local database container ${containerName} is not running. Run \`pnpm db:start\` first. This script never touches a hosted project.`,
  );
}

function main() {
  const containerName = `supabase_db_${readProjectId()}`;
  console.log(
    `LOCAL ONLY: setting a public dev password on the demo staff of the local database (${containerName}). Never run this against a hosted project.`,
  );
  assertLocalContainerRunning(containerName);
  execFileSync(
    "docker",
    [
      "exec",
      "-i",
      containerName,
      "psql",
      "-U",
      DATABASE_USER,
      "-d",
      DATABASE_NAME,
      "--no-psqlrc",
      "--quiet",
      "--single-transaction",
      "--set",
      "ON_ERROR_STOP=1",
    ],
    { input: readFileSync(SEED_FILE, "utf8"), stdio: ["pipe", "inherit", "inherit"] },
  );
  console.log("Done. Sign in as any @demo.church staff with the password in the README.");
}

try {
  main();
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}
