import jsxA11y from "eslint-plugin-jsx-a11y";
import reactHooks from "eslint-plugin-react-hooks";
import { defineConfig } from "eslint/config";
import globals from "globals";

import { createBaseConfig } from "./base.mjs";

const REACT_FILES = ["**/*.{jsx,tsx}"];

/**
 * Base config plus React hooks and accessibility rules.
 * @param {{ tsconfigRootDir: string }} options
 */
export function createReactConfig({ tsconfigRootDir }) {
  return defineConfig(createBaseConfig({ tsconfigRootDir }), {
    files: REACT_FILES,
    extends: [jsxA11y.flatConfigs.strict, reactHooks.configs.flat["recommended-latest"]],
    languageOptions: { globals: { ...globals.browser } },
  });
}
