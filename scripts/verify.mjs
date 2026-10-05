// `pnpm verify`: the one command that runs every quality gate of CLAUDE.md section 6, in order.
// CI runs this same command, so a green local run means a green pipeline.
//
// Steps run in three groups and stop at the first failure:
//   1. Static checks: format, lint, em dash, typecheck, unit tests with coverage, duplicates.
//   2. Database checks: `supabase db reset`, pgTAP, then a fresh GraphQL schema export.
//      They need the local stack (`pnpm db:start`). They run in CI, and locally only when
//      `supabase/` changed against main or when you pass --database.
//   3. Generated files: `codegen:check` fails if the committed schema or types differ from what
//      the schema and the .graphql documents produce. After the database group it therefore
//      catches migrations that were not exported, and without it still catches stale types.
//      It compares against Git, so commit regenerated files before running verify.
import { spawnSync } from "node:child_process";

const DATABASE_FLAG = "--database";
const DATABASE_DIRECTORY = "supabase";
const MAIN_BRANCH_REFS = ["origin/main", "main"];
const GIT_SUCCESS_STATUS = 0;
// pnpm 12 ships as a native binary; older releases are a JavaScript file that needs node.
const JAVASCRIPT_FILE_PATTERN = /\.[cm]?js$/;

const STATIC_STEPS = [
  { label: "Format check", scriptArguments: ["format:check"] },
  { label: "Lint", scriptArguments: ["lint"] },
  { label: "Em dash check", scriptArguments: ["check:em-dash"] },
  { label: "Typecheck", scriptArguments: ["typecheck"] },
  { label: "Unit tests with coverage", scriptArguments: ["test"] },
  { label: "Duplicate detection", scriptArguments: ["duplicates"] },
];

const DATABASE_STEPS = [
  { label: "Database reset", scriptArguments: ["db:reset"] },
  { label: "pgTAP tests", scriptArguments: ["db:test"] },
  { label: "GraphQL schema export", scriptArguments: ["schema:export", "--require-database"] },
];

const GENERATED_FILES_STEP = {
  label: "Generated files up to date",
  scriptArguments: ["codegen:check"],
};

function runGit(gitArguments) {
  return spawnSync("git", gitArguments, { encoding: "utf8" });
}

function findMainRef() {
  return MAIN_BRANCH_REFS.find(
    (ref) => runGit(["rev-parse", "--verify", "--quiet", ref]).status === GIT_SUCCESS_STATUS,
  );
}

function hasDatabaseChanged() {
  const mainRef = findMainRef();
  if (mainRef === undefined) {
    return true;
  }
  const committedChanges = runGit([
    "diff",
    "--name-only",
    `${mainRef}...HEAD`,
    "--",
    DATABASE_DIRECTORY,
  ]);
  const uncommittedChanges = runGit(["status", "--porcelain", "--", DATABASE_DIRECTORY]);
  return `${committedChanges.stdout}${uncommittedChanges.stdout}`.trim().length > 0;
}

function shouldRunDatabaseSteps() {
  return process.env.CI === "true" || process.argv.includes(DATABASE_FLAG) || hasDatabaseChanged();
}

function runStep({ label, scriptArguments }) {
  console.log(`\n==> ${label}: pnpm ${scriptArguments.join(" ")}`);
  const packageManagerScript = process.env.npm_execpath;
  if (packageManagerScript === undefined) {
    console.error("Run this through pnpm: `pnpm verify`.");
    process.exit(1);
  }
  const [command, commandArguments] = JAVASCRIPT_FILE_PATTERN.test(packageManagerScript)
    ? [process.execPath, [packageManagerScript, ...scriptArguments]]
    : [packageManagerScript, scriptArguments];
  const result = spawnSync(command, commandArguments, { stdio: "inherit" });
  if (result.status !== 0) {
    console.error(`\nverify failed at "${label}".`);
    process.exit(result.status ?? 1);
  }
}

const isRunningDatabaseSteps = shouldRunDatabaseSteps();
if (!isRunningDatabaseSteps) {
  console.log(
    `No changes under ${DATABASE_DIRECTORY}/ against main, so the database steps are skipped. ` +
      `Pass ${DATABASE_FLAG} to run them; CI always does.`,
  );
}

const steps = [
  ...STATIC_STEPS,
  ...(isRunningDatabaseSteps ? DATABASE_STEPS : []),
  GENERATED_FILES_STEP,
];
steps.forEach(runStep);
console.log("\nverify passed.");
