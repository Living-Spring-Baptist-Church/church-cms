"use client";

import { ErrorState } from "@lbc/ui";

import { AUTH_COPY } from "@core/copy/auth.copy";
import { ERROR_MESSAGES } from "@core/errors/error-messages.data";

type ErrorPageProps = {
  error: Error & { digest?: string };
  reset: () => void;
};

// Next.js logs the error and its digest on the server; users only ever see the plain message.
export default function ErrorPage({ reset }: ErrorPageProps) {
  return (
    <main id="main-content" className="mx-auto w-full max-w-lg px-4 py-12">
      <ErrorState
        title={AUTH_COPY.errors.heading}
        message={ERROR_MESSAGES.server}
        retryLabel={AUTH_COPY.errors.retry}
        onRetry={reset}
      />
    </main>
  );
}
