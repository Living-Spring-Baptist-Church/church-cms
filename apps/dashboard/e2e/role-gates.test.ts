import { expect, test, type APIRequestContext } from "@playwright/test";

import { readLocalSupabaseEnv } from "./support/local-supabase";
import {
  authStatePath,
  LOCAL_DEV_PASSWORD,
  SEED_STAFF,
  type SeedStaffKey,
} from "./support/seed-staff";

type GraphqlResponse = {
  readonly data?: { readonly getNewVisitorsThisMonth?: number | null } | null;
  readonly errors?: readonly { readonly message: string }[];
};

const NEW_VISITORS_QUERY = "query { getNewVisitorsThisMonth }";

async function signInWithPassword(
  request: APIRequestContext,
  staffKey: SeedStaffKey,
): Promise<string> {
  const { supabaseUrl, supabaseAnonKey } = readLocalSupabaseEnv();
  const response = await request.post(`${supabaseUrl}/auth/v1/token?grant_type=password`, {
    headers: { apikey: supabaseAnonKey },
    data: { email: SEED_STAFF[staffKey].email, password: LOCAL_DEV_PASSWORD },
  });
  expect(response.ok()).toBe(true);
  const body = (await response.json()) as { access_token: string };
  return body.access_token;
}

async function askForNewVisitors(
  request: APIRequestContext,
  accessToken: string,
): Promise<GraphqlResponse> {
  const { supabaseUrl, supabaseAnonKey } = readLocalSupabaseEnv();
  const response = await request.post(`${supabaseUrl}/graphql/v1`, {
    headers: { apikey: supabaseAnonKey, Authorization: `Bearer ${accessToken}` },
    data: { query: NEW_VISITORS_QUERY },
  });
  return (await response.json()) as GraphqlResponse;
}

test.describe("new visitor count through the API", () => {
  test("should return the count when the secretary asks", async ({ request }) => {
    const accessToken = await signInWithPassword(request, "secretary");
    const body = await askForNewVisitors(request, accessToken);
    expect(body.errors).toBeUndefined();
    expect(typeof body.data?.getNewVisitorsThisMonth).toBe("number");
  });

  for (const staffKey of [
    "usher",
    "departmentHead",
    "contentEditor",
    "treasurer",
    "pastor",
  ] as const) {
    test(`should return no count when the ${staffKey} asks with a password-only token`, async ({
      request,
    }) => {
      const accessToken = await signInWithPassword(request, staffKey);
      const body = await askForNewVisitors(request, accessToken);
      expect(body.data?.getNewVisitorsThisMonth ?? null).toBeNull();
      expect(body.errors?.length ?? 0).toBeGreaterThan(0);
    });
  }
});

test.describe("signed out visitor", () => {
  test("should be sent to the login page when opening the overview", async ({ page }) => {
    await page.goto("/");
    await expect(page).toHaveURL(/\/login$/);
    await expect(page.getByRole("navigation", { name: "Main" })).toHaveCount(0);
  });
});

test.describe("usher opening modules directly", () => {
  test.use({ storageState: authStatePath("usher") });

  for (const forbiddenPath of ["/finance", "/audit", "/settings", "/reports", "/members/new"]) {
    test(`should see the not found page when the usher opens ${forbiddenPath}`, async ({
      page,
    }) => {
      await page.goto(forbiddenPath);
      await expect(page.getByRole("heading", { name: "Page not found" })).toBeVisible();
      await expect(page.getByText(/finance|offering|audit/i)).toHaveCount(0);
    });
  }
});
