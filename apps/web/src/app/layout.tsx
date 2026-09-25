import type { Metadata } from "next";
import { Cinzel, Inter } from "next/font/google";
import type { ReactNode } from "react";

import { SITE_COPY } from "@core/copy/site.copy";

import "./globals.css";

const inter = Inter({ subsets: ["latin"], variable: "--font-inter", display: "swap" });
const cinzel = Cinzel({ subsets: ["latin"], variable: "--font-cinzel", display: "swap" });

export const metadata: Metadata = {
  title: SITE_COPY.title,
  description: SITE_COPY.description,
  openGraph: {
    title: SITE_COPY.title,
    description: SITE_COPY.description,
    siteName: SITE_COPY.title,
    type: "website",
  },
};

type RootLayoutProps = {
  children: ReactNode;
};

export default function RootLayout({ children }: RootLayoutProps) {
  return (
    <html lang="en" className={`${inter.variable} ${cinzel.variable}`}>
      <body>{children}</body>
    </html>
  );
}
