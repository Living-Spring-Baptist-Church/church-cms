// GraphQL Code Generator: reads the committed pg_graphql schemas and the .graphql operations,
// and writes typed documents into @lbc/db. Run it with `pnpm codegen`.
//
// Two schemas, because what the API exposes depends on the database role:
//   graphql/schema.graphql            exported as anon, for the public site  -> generated/graphql.ts
//   graphql/dashboard.schema.graphql  exported as authenticated, for staff   -> generated/dashboard.ts
// Operations under graphql/dashboard/ are validated against the authenticated schema, every other
// operation against the anon schema.
const PUBLIC_SCHEMA_FILE = "graphql/schema.graphql";
const DASHBOARD_SCHEMA_FILE = "graphql/dashboard.schema.graphql";
const PUBLIC_GENERATED_FILE = "packages/db/src/generated/graphql.ts";
const DASHBOARD_GENERATED_FILE = "packages/db/src/generated/dashboard.ts";
const SCHEMA_FILES = [PUBLIC_SCHEMA_FILE, DASHBOARD_SCHEMA_FILE];

function createBanner(schemaFile, operationsGlob) {
  return [
    "/* eslint-disable */",
    "// GENERATED FILE. DO NOT EDIT.",
    `// Source: ${schemaFile} and ${operationsGlob}. Regenerate with \`pnpm codegen\`.`,
  ].join("\n");
}

const GENERATOR_CONFIG = {
  useTypeImports: true,
  enumsAsTypes: true,
  avoidOptionals: false,
  defaultScalarType: "unknown",
  // pg_graphql sends 64 bit integers and decimals as strings to avoid precision loss.
  scalars: {
    BigInt: "string",
    BigFloat: "string",
    Date: "string",
    Datetime: "string",
    Time: "string",
    UUID: "string",
    Cursor: "string",
  },
};

function createTarget({ schemaFile, documents, operationsGlob }) {
  return {
    schema: schemaFile,
    documents,
    // typescript-operations 6 writes the schema types an operation uses (enums, scalars) itself,
    // so the separate typescript plugin would declare them twice.
    plugins: [
      { add: { content: createBanner(schemaFile, operationsGlob) } },
      "typescript-operations",
      "typed-document-node",
    ],
    config: GENERATOR_CONFIG,
  };
}

/** @type {import("@graphql-codegen/cli").CodegenConfig} */
const config = {
  ignoreNoDocuments: false,
  generates: {
    [PUBLIC_GENERATED_FILE]: createTarget({
      schemaFile: PUBLIC_SCHEMA_FILE,
      documents: [
        "graphql/**/*.graphql",
        ...SCHEMA_FILES.map((file) => `!${file}`),
        "!graphql/dashboard/**",
      ],
      operationsGlob: "graphql/**/*.graphql",
    }),
    [DASHBOARD_GENERATED_FILE]: createTarget({
      schemaFile: DASHBOARD_SCHEMA_FILE,
      documents: ["graphql/dashboard/**/*.graphql"],
      operationsGlob: "graphql/dashboard/**/*.graphql",
    }),
  },
};

export default config;
