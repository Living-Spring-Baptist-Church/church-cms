import Link from "next/link";

import {
  Button,
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@lbc/ui";

import { HOME_COPY } from "@core/copy/home.copy";
import { ROUTES } from "@core/data/routes.data";

export default function HomePage() {
  return (
    <main className="mx-auto flex min-h-screen max-w-lg flex-col justify-center gap-8 px-4 py-12">
      <section aria-labelledby="home-heading" className="flex flex-col gap-6">
        <h1 id="home-heading" className="text-2xl font-semibold text-primary">
          {HOME_COPY.heading}
        </h1>
        <Card>
          <CardHeader>
            <CardTitle as="h2">{HOME_COPY.cardTitle}</CardTitle>
            <CardDescription>{HOME_COPY.cardDescription}</CardDescription>
          </CardHeader>
          <CardContent>
            <p>{HOME_COPY.cardBody}</p>
          </CardContent>
          <CardFooter>
            <Button asChild>
              <Link href={ROUTES.login}>{HOME_COPY.signInAction}</Link>
            </Button>
          </CardFooter>
        </Card>
      </section>
    </main>
  );
}
