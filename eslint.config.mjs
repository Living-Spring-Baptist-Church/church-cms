import { createBaseConfig } from "@lbc/config/eslint/base";
import { defineConfig, globalIgnores } from "eslint/config";

const SCRIPT_FILES = ["scripts/**/*.mjs"];

export default defineConfig(
  // Each workspace lints itself through its own eslint.config.mjs.
  globalIgnores(["apps/", "packages/"]),
  createBaseConfig({ tsconfigRootDir: import.meta.dirname }),
  // Repo scripts are command line tools, so they report through the console.
  { files: SCRIPT_FILES, rules: { "no-console": "off" } },
);
