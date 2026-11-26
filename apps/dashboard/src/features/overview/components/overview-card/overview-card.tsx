import type { ReactNode } from "react";

import { Card, CardContent, CardHeader, CardTitle } from "@lbc/ui";

type OverviewCardProps = {
  title: string;
  children: ReactNode;
};

/** The frame every overview figure shares: a card with its title as the level 2 heading. */
export function OverviewCard({ title, children }: OverviewCardProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle as="h2">{title}</CardTitle>
      </CardHeader>
      <CardContent>{children}</CardContent>
    </Card>
  );
}
