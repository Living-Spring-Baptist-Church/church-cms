import { fileURLToPath } from "node:url";

import { defineConfig } from "vitest/config";

const COVERAGE_THRESHOLD_PERCENT = 80;

function sourcePath(folder: string) {
  return fileURLToPath(new URL(`./src/${folder}`, import.meta.url));
}

export default defineConfig({
  resolve: {
    alias: {
      "@core": sourcePath("core"),
      "@features": sourcePath("features"),
      "@config": sourcePath("config"),
      "@helpers": sourcePath("helpers"),
    },
  },
  test: {
    environment: "jsdom",
    setupFiles: ["./src/test/setup.ts"],
    include: ["src/**/*.test.{ts,tsx}"],
    coverage: {
      provider: "v8",
      include: [
        "src/config/**/*.ts",
        "src/core/auth/**/*.ts",
        "src/core/errors/**/*.ts",
        "src/core/schemas/**/*.ts",
        "src/core/services/**/*.ts",
        "src/features/**/*.tsx",
        "src/helpers/**/*.ts",
        "src/proxy.ts",
      ],
      // Server components and layouts only compose tested pieces: login-screen needs the Next.js
      // runtime to render and the app header is presentational, both covered by the end to end run.
      exclude: [
        "src/**/*.test.{ts,tsx}",
        "src/features/**/login-screen.tsx",
        "src/features/shell/**",
        "src/**/*-test-fakes.ts",
      ],
      reporter: ["text"],
      thresholds: { lines: COVERAGE_THRESHOLD_PERCENT, branches: COVERAGE_THRESHOLD_PERCENT },
    },
  },
});
