import { createNextConfig } from "@lbc/config/eslint/next";
import { defineConfig, globalIgnores } from "eslint/config";

// Playwright output and saved sign-in state are generated and gitignored in e2e/.gitignore.
const E2E_ARTIFACT_PATHS = ["e2e/.auth/", "e2e/test-results/", "e2e/playwright-report/"];

export default defineConfig(
  globalIgnores(E2E_ARTIFACT_PATHS),
  createNextConfig({ tsconfigRootDir: import.meta.dirname }),
);
