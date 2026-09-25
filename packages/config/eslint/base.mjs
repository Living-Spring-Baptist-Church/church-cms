import js from "@eslint/js";
import prettierConfig from "eslint-config-prettier";
import { defineConfig, globalIgnores } from "eslint/config";
import globals from "globals";
import tseslint from "typescript-eslint";

const MAX_COMPLEXITY = 10;
const MAX_LINES_PER_FUNCTION = 80;
const MAX_LINES_PER_FILE = 400;
const MAX_PARAMS = 3;
const ALLOWED_MAGIC_NUMBERS = [-1, 0, 1, 2];

const JS_FILES = ["**/*.{js,mjs,cjs}"];
const TEST_FILES = ["**/*.test.{ts,tsx}", "**/test/**"];
const CONFIG_FILES = ["**/*.config.{js,mjs,cjs,ts,mts}", "**/eslint/*.mjs", "**/prettier/*.mjs"];

const IGNORED_PATHS = [
  "**/node_modules/",
  "**/.next/",
  "**/.turbo/",
  "**/coverage/",
  "**/dist/",
  "**/out/",
  "**/next-env.d.ts",
];

export const RESTRICTED_ICON_IMPORTS = {
  paths: [
    {
      name: "lucide-react",
      message: 'Use <Icon name="..." /> from @lbc/ui. Only packages/ui may import lucide-react.',
    },
  ],
};

const qualityRules = {
  complexity: ["error", MAX_COMPLEXITY],
  "max-lines-per-function": [
    "error",
    { max: MAX_LINES_PER_FUNCTION, skipBlankLines: true, skipComments: true },
  ],
  "max-lines": ["error", { max: MAX_LINES_PER_FILE }],
  "max-params": "off",
  "@typescript-eslint/max-params": ["error", { max: MAX_PARAMS }],
  "no-magic-numbers": "off",
  "@typescript-eslint/no-magic-numbers": [
    "error",
    {
      ignore: ALLOWED_MAGIC_NUMBERS,
      ignoreEnums: true,
      ignoreNumericLiteralTypes: true,
      ignoreReadonlyClassProperties: true,
      ignoreTypeIndexes: true,
    },
  ],
  "@typescript-eslint/no-explicit-any": "error",
  "no-console": "error",
  "no-restricted-imports": ["error", RESTRICTED_ICON_IMPORTS],
};

/**
 * Shared flat config for every workspace.
 * @param {{ tsconfigRootDir: string }} options
 */
export function createBaseConfig({ tsconfigRootDir }) {
  return defineConfig(
    globalIgnores(IGNORED_PATHS),
    js.configs.recommended,
    tseslint.configs.strictTypeChecked,
    {
      languageOptions: {
        parserOptions: { projectService: true, tsconfigRootDir },
        globals: { ...globals.node },
      },
      rules: qualityRules,
    },
    { files: JS_FILES, extends: [tseslint.configs.disableTypeChecked] },
    {
      files: [...TEST_FILES, ...CONFIG_FILES],
      rules: { "@typescript-eslint/no-magic-numbers": "off", "max-lines-per-function": "off" },
    },
    prettierConfig,
  );
}
