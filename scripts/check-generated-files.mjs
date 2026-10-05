// Fails when the generated GraphQL files differ from what Git has (AC5 of LBC-14).
// Run after `pnpm codegen:generate`: if the schema or a .graphql document changed without the
// generated types being regenerated and committed, the working tree differs and this exits 1.
import { execFileSync } from "node:child_process";

const GENERATED_PATHS = ["graphql/schema.graphql", "packages/db/src/generated"];

const changedFiles = execFileSync("git", ["status", "--porcelain", "--", ...GENERATED_PATHS], {
  encoding: "utf8",
}).trim();

if (changedFiles.length > 0) {
  console.error(
    `Generated GraphQL files are out of date. Run \`pnpm codegen\` and commit the result:\n${changedFiles}`,
  );
  process.exit(1);
}
console.log("Generated GraphQL files are up to date.");
