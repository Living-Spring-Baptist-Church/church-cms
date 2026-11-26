import { test as setup } from "@playwright/test";

import { authStatePath, SEED_STAFF_KEYS } from "./support/seed-staff";
import { signInAs } from "./support/sign-in";

for (const staffKey of SEED_STAFF_KEYS) {
  setup(
    `should sign in and keep the session when the ${staffKey} uses the seed account`,
    async ({ page }) => {
      await signInAs(page, staffKey);
      await page.context().storageState({ path: authStatePath(staffKey) });
    },
  );
}
