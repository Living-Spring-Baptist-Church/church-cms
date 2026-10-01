// Scans staged changes for secrets with gitleaks. CI enforces the same scan (LBC-15).
import { spawnSync } from "node:child_process";

const GITLEAKS_BINARY = "gitleaks";
const GITLEAKS_ARGUMENTS = ["git", "--pre-commit", "--staged", "--redact", "--verbose"];

function isGitleaksInstalled() {
  const versionCheck = spawnSync(GITLEAKS_BINARY, ["version"], { stdio: "ignore" });
  return versionCheck.error === undefined && versionCheck.status === 0;
}

function runGitleaks() {
  if (!isGitleaksInstalled()) {
    console.warn(
      "Warning: gitleaks is not installed, so the local secret scan was skipped. " +
        "Install it from https://github.com/gitleaks/gitleaks. CI runs the scan on every pull request.",
    );
    return;
  }

  const scan = spawnSync(GITLEAKS_BINARY, GITLEAKS_ARGUMENTS, { stdio: "inherit" });
  if (scan.status !== 0) {
    console.error(
      "gitleaks found a possible secret in the staged changes. Remove it before committing.",
    );
    process.exit(scan.status ?? 1);
  }
}

runGitleaks();
