import { Card, CardContent, CardHeader, Skeleton } from "@lbc/ui";

export default function LoginLoading() {
  return (
    <main className="mx-auto flex min-h-screen w-full max-w-md flex-col justify-center gap-6 px-4 py-8">
      <Skeleton className="h-24 w-48 self-center" />
      <Card>
        <CardHeader>
          <Skeleton className="h-8 w-3/4" />
          <Skeleton className="h-4 w-full" />
        </CardHeader>
        <CardContent className="flex flex-col gap-4">
          <Skeleton className="h-11 w-full" />
          <Skeleton className="h-11 w-full" />
          <Skeleton className="h-11 w-full" />
        </CardContent>
      </Card>
    </main>
  );
}
