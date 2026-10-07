import { NextResponse } from "next/server";

import { createRequestAuth, clearActivity } from "@core/auth/request-context";
import { ROUTES } from "@core/data/routes.data";

// Reached when a signed-in account turned out to be deactivated: end the session, back to login.
export async function GET(request: Request) {
  const auth = await createRequestAuth("writable");
  await auth.signOut();
  await clearActivity();
  return NextResponse.redirect(new URL(ROUTES.login, request.url));
}
