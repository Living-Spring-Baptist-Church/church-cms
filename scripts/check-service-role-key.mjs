// Fails when the Supabase service role key is referenced where it could reach a Next.js app or a
// Vercel project (ADR-004, ADR-008, CLAUDE.md rule 8). The key belongs to edge functions only.
// Scans every file git tracks or would track under apps/, plus any vercel.json in the repository.
// Usage: node scripts/check-service-role-key.mjs
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { basename } from "node:path";

const NUL_CHARACTER = "\u0000";
const APPS_PREFIX = "apps/";
const VERCEL_CONFIG_FILE_NAME = "vercel.json";
const SERVICE_ROLE_PATTERN = /service[_-]?role/i;
// 256 MiB, enough for the full file list of a large repository.
const MAX_GIT_OUTPUT_BYTES = 268_435_456;

function listCandidateFilePaths() {
  return execFileSync("git", ["ls-files", "--cached", "--others", "--exclude-standard", "-z"], {
    encoding: "utf8",
    maxBuffer: MAX_GIT_OUTPUT_BYTES,
  })
    .split(NUL_CHARACTER)
    .filter(
      (filePath) =>
        filePath.startsWith(APPS_PREFIX) || basename(filePath) === VERCEL_CONFIG_FILE_NAME,
    );
}

function findViolationLines(filePath) {
  if (!existsSync(filePath)) {
    return [];
  }
  const fileContent = readFileSync(filePath, "utf8");
  if (fileContent.includes(NUL_CHARACTER)) {
    return [];
  }
  return fileContent
    .split("\n")
    .flatMap((lineText, lineIndex) =>
      SERVICE_ROLE_PATTERN.test(lineText) ? [`${filePath}:${String(lineIndex + 1)}`] : [],
    );
}

function checkServiceRoleKey() {
  const violations = listCandidateFilePaths().flatMap(findViolationLines);
  if (violations.length > 0) {
    console.error(
      "The Supabase service role key must never be used in apps/ or in a vercel.json. Remove:",
    );
    violations.forEach((violation) => {
      console.error(`  ${violation}`);
    });
    process.exit(1);
  }
  console.log("No service role key references found in apps/ or vercel.json files.");
}

checkServiceRoleKey();
