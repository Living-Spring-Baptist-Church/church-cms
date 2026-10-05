// GraphQL Code Generator: reads the committed pg_graphql schema and every .graphql operation,
// and writes typed documents into @lbc/db. Run it with `pnpm codegen`.
const GENERATED_FILE = "packages/db/src/generated/graphql.ts";
const GENERATED_BANNER = [
  "/* eslint-disable */",
  "// GENERATED FILE. DO NOT EDIT.",
  "// Source: graphql/schema.graphql and graphql/**/*.graphql. Regenerate with `pnpm codegen`.",
].join("\n");

/** @type {import("@graphql-codegen/cli").CodegenConfig} */
const config = {
  schema: "graphql/schema.graphql",
  documents: ["graphql/**/*.graphql", "!graphql/schema.graphql"],
  ignoreNoDocuments: false,
  generates: {
    [GENERATED_FILE]: {
      plugins: [
        { add: { content: GENERATED_BANNER } },
        "typescript",
        "typescript-operations",
        "typed-document-node",
      ],
      config: {
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
      },
    },
  },
};

export default config;
