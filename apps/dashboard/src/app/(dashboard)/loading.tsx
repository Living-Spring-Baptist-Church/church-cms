import { Card, CardContent, CardHeader, Skeleton } from "@lbc/ui";

/** Mirrors the overview: a heading, quick actions, then the cards. Shown while a page's data loads. */
export default function DashboardLoading() {
  return (
    <main className="mx-auto flex w-full max-w-5xl flex-col gap-8 px-4 py-8">
      <Skeleton className="h-8 w-2/3" />
      <div className="flex gap-3">
        <Skeleton className="h-11 w-40" />
        <Skeleton className="h-11 w-40" />
      </div>
      <ul className="grid gap-6 md:grid-cols-2">
        <li>
          <Card>
            <CardHeader>
              <Skeleton className="h-6 w-1/2" />
            </CardHeader>
            <CardContent className="grid grid-cols-2 gap-4 sm:grid-cols-4">
              <Skeleton className="h-12 w-full" />
              <Skeleton className="h-12 w-full" />
              <Skeleton className="h-12 w-full" />
              <Skeleton className="h-12 w-full" />
            </CardContent>
          </Card>
        </li>
      </ul>
    </main>
  );
}
