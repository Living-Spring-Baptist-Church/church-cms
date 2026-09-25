import { createReactConfig } from "@lbc/config/eslint/react";
import { defineConfig } from "eslint/config";

export default defineConfig(createReactConfig({ tsconfigRootDir: import.meta.dirname }), {
  // The UI kit is the one place allowed to wrap lucide-react behind <Icon>.
  rules: { "no-restricted-imports": "off" },
});
