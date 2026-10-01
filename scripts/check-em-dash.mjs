// Fails when a text file contains an em dash (CLAUDE.md rule 10).
// Usage: node scripts/check-em-dash.mjs            every file git tracks or would track
//        node scripts/check-em-dash.mjs --staged   only the staged content (pre-commit)
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";

const EM_DASH = "\u2014";
const NUL_CHARACTER = "\u0000";
const STAGED_FLAG = "--staged";
// 256 MiB, enough for the full file list of a large repository.
const MAX_GIT_OUTPUT_BYTES = 268_435_456;

function runGit(gitArguments) {
  return execFileSync("git", gitArguments, { encoding: "utf8", maxBuffer: MAX_GIT_OUTPUT_BYTES });
}

function listFilePaths(isStagedOnly) {
  const gitArguments = isStagedOnly
    ? ["diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z"]
    : ["ls-files", "--cached", "--others", "--exclude-standard", "-z"];
  return runGit(gitArguments)
    .split(NUL_CHARACTER)
    .filter((filePath) => filePath.length > 0);
}

function readFileContent(filePath, isStagedOnly) {
  if (isStagedOnly) {
    return runGit(["show", `:${filePath}`]);
  }
  return existsSync(filePath) ? readFileSync(filePath, "utf8") : "";
}

function findEmDashLineNumbers(fileContent) {
  const isBinary = fileContent.includes(NUL_CHARACTER);
  if (isBinary) {
    return [];
  }
  return fileContent
    .split("\n")
    .flatMap((lineText, lineIndex) => (lineText.includes(EM_DASH) ? [lineIndex + 1] : []));
}

function checkEmDashes() {
  const isStagedOnly = process.argv.includes(STAGED_FLAG);
  const violations = listFilePaths(isStagedOnly).flatMap((filePath) =>
    findEmDashLineNumbers(readFileContent(filePath, isStagedOnly)).map(
      (lineNumber) => `${filePath}:${String(lineNumber)}`,
    ),
  );

  if (violations.length > 0) {
    console.error("Em dashes are not allowed. Rewrite with a period, comma, colon or 'and':");
    violations.forEach((violation) => {
      console.error(`  ${violation}`);
    });
    process.exit(1);
  }
  console.log("No em dashes found.");
}

checkEmDashes();
