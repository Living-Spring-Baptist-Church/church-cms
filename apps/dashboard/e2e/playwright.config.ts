import { defineConfig, devices } from "@playwright/test";

import {
  LOCAL_SUPABASE_ANON_KEY_VARIABLE,
  LOCAL_SUPABASE_URL_VARIABLE,
  readLocalSupabaseEnv,
} from "./support/local-supabase";

// LOCAL ONLY: needs the local Supabase stack. Run with `pnpm test:e2e` from the repository root.
// localhost, not 127.0.0.1: Next 16 dev blocks its dev resources for other origins, so React never hydrates.
const DASHBOARD_PORT = 3000;
const BASE_URL = `http://localhost:${String(DASHBOARD_PORT)}`;
const MOBILE_VIEWPORT = { width: 375, height: 812 };
const DESKTOP_VIEWPORT = { width: 1280, height: 800 };
const SERVER_START_TIMEOUT_MILLISECONDS = 420_000;
const TEST_TIMEOUT_MILLISECONDS = 90_000;
// A production build by default: it is what staff use, and next dev adds dev-only checks and overlays.
// Set E2E_SERVER_MODE=dev to test against the dev server instead.
const PRODUCTION_SERVER_COMMAND = `pnpm --filter @lbc/dashboard build && pnpm --filter @lbc/dashboard exec next start --port ${String(DASHBOARD_PORT)}`;
const DEV_SERVER_COMMAND = "pnpm --filter @lbc/dashboard dev";
const serverCommand =
  process.env.E2E_SERVER_MODE === "dev" ? DEV_SERVER_COMMAND : PRODUCTION_SERVER_COMMAND;

const localSupabase = readLocalSupabaseEnv();
process.env[LOCAL_SUPABASE_URL_VARIABLE] = localSupabase.supabaseUrl;
process.env[LOCAL_SUPABASE_ANON_KEY_VARIABLE] = localSupabase.supabaseAnonKey;

export default defineConfig({
  testDir: ".",
  testMatch: /.*\.test\.ts$/,
  outputDir: "./test-results",
  timeout: TEST_TIMEOUT_MILLISECONDS,
  fullyParallel: false,
  workers: 1,
  forbidOnly: Boolean(process.env.CI),
  reporter: [["list"]],
  globalSetup: "./global-setup.ts",
  use: {
    baseURL: BASE_URL,
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    timezoneId: "Africa/Accra",
    locale: "en-GH",
  },
  projects: [
    { name: "setup", testMatch: /auth\.setup\.ts$/ },
    {
      name: "desktop",
      dependencies: ["setup"],
      use: { ...devices["Desktop Chrome"], viewport: DESKTOP_VIEWPORT },
    },
    {
      name: "mobile-375",
      dependencies: ["setup"],
      use: {
        ...devices["Desktop Chrome"],
        viewport: MOBILE_VIEWPORT,
        isMobile: true,
        hasTouch: true,
      },
    },
  ],
  webServer: {
    command: serverCommand,
    url: `${BASE_URL}/login`,
    reuseExistingServer: true,
    timeout: SERVER_START_TIMEOUT_MILLISECONDS,
    env: {
      [LOCAL_SUPABASE_URL_VARIABLE]: localSupabase.supabaseUrl,
      [LOCAL_SUPABASE_ANON_KEY_VARIABLE]: localSupabase.supabaseAnonKey,
    },
  },
});
