const MAX_HEADER_LENGTH = 72;

const commitlintConfig = {
  extends: ["@commitlint/config-conventional"],
  rules: {
    "header-max-length": [2, "always", MAX_HEADER_LENGTH],
  },
};

export default commitlintConfig;
