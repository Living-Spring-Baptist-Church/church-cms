import { defineConfig } from "vitest/config";

const COVERAGE_THRESHOLD_PERCENT = 80;

export default defineConfig({
  test: {
    environment: "jsdom",
    setupFiles: ["./src/test/setup.ts"],
    include: ["src/**/*.test.{ts,tsx}"],
    coverage: {
      provider: "v8",
      include: ["src/**/*.{ts,tsx}"],
      exclude: ["src/**/*.test.{ts,tsx}", "src/test/**", "src/index.ts"],
      reporter: ["text", "html"],
      thresholds: {
        lines: COVERAGE_THRESHOLD_PERCENT,
        branches: COVERAGE_THRESHOLD_PERCENT,
      },
    },
  },
});
