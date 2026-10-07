import { defineConfig } from "vitest/config";

const COVERAGE_THRESHOLD_PERCENT = 80;

export default defineConfig({
  test: {
    environment: "node",
    include: ["src/**/*.test.ts"],
    coverage: {
      provider: "v8",
      include: ["src/**/*.ts"],
      exclude: ["src/**/*.test.ts", "src/index.ts", "src/auth/auth.port.ts"],
      reporter: ["text"],
      thresholds: { lines: COVERAGE_THRESHOLD_PERCENT, branches: COVERAGE_THRESHOLD_PERCENT },
    },
  },
});
