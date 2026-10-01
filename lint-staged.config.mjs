// Look up the nearest eslint.config.mjs per file, so each workspace keeps its own rules.
const ESLINT_COMMAND =
  "eslint --max-warnings 0 --no-warn-ignored --flag v10_config_lookup_from_file";

const lintStagedConfig = {
  "*.{js,mjs,cjs,ts,tsx}": [ESLINT_COMMAND, "prettier --write"],
  "!(*.{js,mjs,cjs,ts,tsx})": "prettier --write --ignore-unknown",
};

export default lintStagedConfig;
