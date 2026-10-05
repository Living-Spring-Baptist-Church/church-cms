import { defineConfig } from "vitest/config";

const COVERAGE_THRESHOLD_PERCENT = 80;

export default defineConfig({
  test: {
    environment: "node",
    include: ["src/**/*.test.{ts,tsx}"],
    coverage: {
      provider: "v8",
      include: ["src/config/**/*.ts", "src/core/services/**/*.ts", "src/helpers/**/*.ts"],
      exclude: ["src/**/*.test.{ts,tsx}"],
      reporter: ["text"],
      thresholds: { lines: COVERAGE_THRESHOLD_PERCENT, branches: COVERAGE_THRESHOLD_PERCENT },
    },
  },
});
