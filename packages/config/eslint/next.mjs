import nextPlugin from "@next/eslint-plugin-next";
import { defineConfig } from "eslint/config";

import { createReactConfig } from "./react.mjs";

/**
 * React config plus the Next.js core web vitals rules, for apps/*.
 * @param {{ tsconfigRootDir: string }} options
 */
export function createNextConfig({ tsconfigRootDir }) {
  return defineConfig(createReactConfig({ tsconfigRootDir }), {
    plugins: { "@next/next": nextPlugin },
    rules: {
      ...nextPlugin.configs.recommended.rules,
      ...nextPlugin.configs["core-web-vitals"].rules,
      // Only meaningful for the pages/ router; both apps use the App Router.
      "@next/next/no-html-link-for-pages": "off",
    },
  });
}
