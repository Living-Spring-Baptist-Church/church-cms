"use client";

import { ErrorState } from "@lbc/ui";

import { AUTH_COPY } from "@core/copy/auth.copy";
import { ERROR_MESSAGES } from "@core/errors/error-messages.data";

import "./globals.css";

type GlobalErrorProps = {
  error: Error & { digest?: string };
  reset: () => void;
};

// Replaces the root layout when it fails, so it brings its own html and body.
export default function GlobalError({ reset }: GlobalErrorProps) {
  return (
    <html lang="en">
      <body>
        <main id="main-content" className="mx-auto w-full max-w-lg px-4 py-12">
          <ErrorState
            title={AUTH_COPY.errors.heading}
            message={ERROR_MESSAGES.server}
            retryLabel={AUTH_COPY.errors.retry}
            onRetry={reset}
          />
        </main>
      </body>
    </html>
  );
}
