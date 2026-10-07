// Exports the pg_graphql schema of the local database as SDL, twice: as anon into
// graphql/schema.graphql (public site) and as authenticated into graphql/dashboard.schema.graphql
// (staff dashboard). GraphQL Code Generator reads those committed files, so `pnpm codegen` works
// without Docker.
//
// How it works: the introspection query runs inside Postgres through graphql.resolve(), as the
// `anon` and `authenticated` database roles, over `docker exec psql` into the local Supabase database container.
// No HTTP call, no API key and no service role key is involved (CLAUDE.md rule 8).
//
// pg_graphql 1.6 answers introspection only when the schema comment sets "introspection": true,
// and production keeps it off (ADR-015). So the script switches it on inside a transaction that
// is always rolled back: the database is never changed.
//
// Usage:
//   pnpm db:start
//   pnpm schema:export
//
// When the database container is not running the script says so and keeps the committed file.
// Pass --require-database to fail instead (used when you must refresh the schema).
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { buildClientSchema, getIntrospectionQuery, printSchema } from "graphql";

// The public site reads as anon. Dashboard operations are typed against what a signed-in staff
// member can call, because functions such as logAuditEvent are granted to authenticated only.
const SCHEMA_EXPORTS = [
  { role: "anon", file: "graphql/schema.graphql" },
  { role: "authenticated", file: "graphql/dashboard.schema.graphql" },
];
const SUPABASE_CONFIG_FILE = "supabase/config.toml";
const DATABASE_USER = "postgres";
const DATABASE_NAME = "postgres";
const REQUIRE_DATABASE_FLAG = "--require-database";
// 64 MiB, far above any realistic introspection result.
const MAX_OUTPUT_BYTES = 67_108_864;

function readProjectId() {
  const config = readFileSync(SUPABASE_CONFIG_FILE, "utf8");
  const match = /^project_id\s*=\s*"([^"]+)"/m.exec(config);
  if (!match?.[1]) {
    throw new Error(`No project_id found in ${SUPABASE_CONFIG_FILE}`);
  }
  return match[1];
}

const ENABLE_INTROSPECTION_SQL = `
do $lbc_enable$
declare
  schema_comment text := obj_description('public'::regnamespace, 'pg_namespace');
  updated_comment text := regexp_replace(schema_comment, '^@graphql\\(\\{', '@graphql({"introspection": true, ');
begin
  if schema_comment is null or updated_comment = schema_comment then
    raise exception 'The public schema comment must start with @graphql({...}), see the base migration';
  end if;
  execute format('comment on schema public is %L', updated_comment);
end
$lbc_enable$;`;

function buildIntrospectionSql(role) {
  return [
    "begin;",
    ENABLE_INTROSPECTION_SQL,
    `set local role ${role};`,
    `select graphql.resolve($lbc_query$${getIntrospectionQuery()}$lbc_query$);`,
    "rollback;",
  ].join("\n");
}

function runInContainer(containerName, sql) {
  return execFileSync(
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
      "--tuples-only",
      "--no-align",
      "--quiet",
      "--set",
      "ON_ERROR_STOP=1",
    ],
    { encoding: "utf8", input: sql, maxBuffer: MAX_OUTPUT_BYTES, stdio: ["pipe", "pipe", "pipe"] },
  );
}

function extractIntrospection(psqlOutput) {
  const resultLine = psqlOutput
    .split("\n")
    .map((line) => line.trim())
    .find((line) => line.startsWith("{"));
  if (!resultLine) {
    throw new Error("The database returned no GraphQL result");
  }
  const result = JSON.parse(resultLine);
  if (result.errors) {
    throw new Error(`pg_graphql returned errors: ${JSON.stringify(result.errors)}`);
  }
  return result.data;
}

function writeSchema(introspection, schemaFile) {
  const sdl = printSchema(buildClientSchema(introspection));
  mkdirSync(dirname(schemaFile), { recursive: true });
  writeFileSync(schemaFile, `${sdl}\n`);
  console.log(`Wrote ${schemaFile}`);
}

function exportAll(containerName) {
  // Introspect everything before writing, so a failure never leaves one schema updated and one stale.
  const introspections = SCHEMA_EXPORTS.map(({ role, file }) => ({
    file,
    introspection: extractIntrospection(runInContainer(containerName, buildIntrospectionSql(role))),
  }));
  introspections.forEach(({ file, introspection }) => {
    writeSchema(introspection, file);
  });
}

function main() {
  const containerName = `supabase_db_${readProjectId()}`;
  try {
    exportAll(containerName);
  } catch (error) {
    const reason = error instanceof Error ? error.message.split("\n")[0] : String(error);
    const message = `Database container ${containerName} is not reachable (${reason}). Run \`pnpm db:start\` and re-run \`pnpm schema:export\` to refresh the schemas.`;
    if (process.argv.includes(REQUIRE_DATABASE_FLAG)) {
      throw new Error(message);
    }
    console.warn(`${message} Keeping the committed schema files.`);
  }
}

try {
  main();
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}
