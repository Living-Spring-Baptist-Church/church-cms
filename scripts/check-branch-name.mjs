// Pre-push guard for CLAUDE.md section 5. Git passes one line per ref on stdin:
// <local ref> <local sha> <remote ref> <remote sha>
// Run by hand, it checks the current branch. In Git Bash, redirect stdin so it does not wait:
//   node scripts/check-branch-name.mjs < /dev/null
import { execFileSync } from "node:child_process";
import { fstatSync, readFileSync } from "node:fs";

const ALLOWED_BRANCH_TYPES = [
  "feat",
  "fix",
  "chore",
  "docs",
  "refactor",
  "test",
  "perf",
  "hotfix",
  "release",
];
// Long-lived branches that already exist on origin and are pushed to directly.
const LONG_LIVED_BRANCH_NAMES = ["dev", "staging", "production"];
// main only changes through a merged pull request.
const PROTECTED_BRANCH_NAMES = ["main"];
const BRANCH_REF_PREFIX = "refs/heads/";
const DETACHED_HEAD_NAME = "HEAD";
const STDIN_FILE_DESCRIPTOR = 0;
const DELETED_REF_SHA_PATTERN = /^0+$/;
const BRANCH_NAME_PATTERN = new RegExp(
  `^(${ALLOWED_BRANCH_TYPES.join("|")})/LBC-[1-9][0-9]*-[a-z0-9]+(-[a-z0-9]+)*$`,
);

// Git feeds the hook through a pipe. Windows reports a pipe as neither a file nor a device.
function isStdinFromHook() {
  if (process.stdin.isTTY) {
    return false;
  }
  const stdinStats = fstatSync(STDIN_FILE_DESCRIPTOR);
  return stdinStats.isFIFO() || !(stdinStats.isFile() || stdinStats.isCharacterDevice());
}

function readPushedRefLines() {
  return readFileSync(STDIN_FILE_DESCRIPTOR, "utf8")
    .split(/\r?\n/)
    .map((refLine) => refLine.trim())
    .filter((refLine) => refLine.length > 0);
}

function parsePushedBranch(refLine) {
  const [, localSha = "", remoteRef = ""] = refLine.split(/\s+/);
  if (!remoteRef.startsWith(BRANCH_REF_PREFIX)) {
    return null;
  }
  return {
    branchName: remoteRef.slice(BRANCH_REF_PREFIX.length),
    isDeletion: DELETED_REF_SHA_PATTERN.test(localSha),
  };
}

function findBranchProblem({ branchName, isDeletion }) {
  if (PROTECTED_BRANCH_NAMES.includes(branchName)) {
    return `Pushing to "${branchName}" is not allowed. Open a pull request instead.`;
  }
  const isAllowed =
    isDeletion ||
    LONG_LIVED_BRANCH_NAMES.includes(branchName) ||
    BRANCH_NAME_PATTERN.test(branchName);
  return isAllowed
    ? null
    : `Branch "${branchName}" does not match <type>/LBC-<n>-<short-description>.`;
}

function readCurrentBranchName() {
  return execFileSync("git", ["rev-parse", "--abbrev-ref", "HEAD"], { encoding: "utf8" }).trim();
}

function listBranchesToCheck() {
  if (isStdinFromHook()) {
    // An empty list from git means nothing is being pushed, so there is nothing to check.
    return readPushedRefLines()
      .map(parsePushedBranch)
      .filter((pushedBranch) => pushedBranch !== null);
  }
  // Run by hand: check the current branch, unless HEAD is detached.
  const currentBranchName = readCurrentBranchName();
  if (currentBranchName === DETACHED_HEAD_NAME) {
    console.log("Detached HEAD: no branch to check.");
    return [];
  }
  return [{ branchName: currentBranchName, isDeletion: false }];
}

function checkBranchNames() {
  const problems = listBranchesToCheck()
    .map(findBranchProblem)
    .filter((problem) => problem !== null);

  if (problems.length > 0) {
    problems.forEach((problem) => {
      console.error(problem);
    });
    console.error(
      `Allowed types: ${ALLOWED_BRANCH_TYPES.join(", ")}. Example: feat/LBC-27-member-search`,
    );
    process.exit(1);
  }
}

checkBranchNames();
