import Link from "next/link";

import { Button } from "@lbc/ui";

import { AUTH_COPY } from "@core/copy/auth.copy";
import { ROUTES } from "@core/data/routes.data";

export default function NotFoundPage() {
  return (
    <main id="main-content" className="mx-auto flex w-full max-w-lg flex-col gap-4 px-4 py-12">
      <h1 className="text-2xl font-semibold text-primary">{AUTH_COPY.errors.notFoundHeading}</h1>
      <p>{AUTH_COPY.errors.notFoundBody}</p>
      <Button asChild className="self-start">
        <Link href={ROUTES.home}>{AUTH_COPY.errors.notFoundAction}</Link>
      </Button>
    </main>
  );
}
