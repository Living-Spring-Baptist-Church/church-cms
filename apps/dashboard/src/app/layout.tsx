import type { Metadata } from "next";
import { Inter } from "next/font/google";
import type { ReactNode } from "react";

import { SITE_COPY } from "@core/copy/site.copy";
import { buildColorSchemeScript } from "@helpers/theme.utils";

import "./globals.css";

const inter = Inter({ subsets: ["latin"], variable: "--font-inter", display: "swap" });
const COLOR_SCHEME_SCRIPT = buildColorSchemeScript();

export const metadata: Metadata = {
  title: SITE_COPY.title,
  description: SITE_COPY.description,
  robots: { index: false, follow: false },
};

type RootLayoutProps = {
  children: ReactNode;
};

export default function RootLayout({ children }: RootLayoutProps) {
  return (
    // The color scheme script adds the dark class before hydration, so React must not flag it.
    <html lang="en" className={inter.variable} suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: COLOR_SCHEME_SCRIPT }} />
      </head>
      <body>{children}</body>
    </html>
  );
}
