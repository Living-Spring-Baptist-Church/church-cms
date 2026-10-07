/* eslint-disable */
// GENERATED FILE. DO NOT EDIT.
// Source: graphql/dashboard.schema.graphql and graphql/dashboard/**/*.graphql. Regenerate with `pnpm codegen`.
/** Internal type. DO NOT USE DIRECTLY. */
type Exact<T extends { [key: string]: unknown }> = { [K in keyof T]: T[K] };
/** Internal type. DO NOT USE DIRECTLY. */
export type Incremental<T> = T | { [P in keyof T]?: P extends ' $fragmentName' | '__typename' ? T[P] : never };
import type { TypedDocumentNode as DocumentNode } from '@graphql-typed-document-node/core';
export type AppRole =
  | 'content_editor'
  | 'department_head'
  | 'pastor'
  | 'secretary'
  | 'super_admin'
  | 'treasurer'
  | 'usher';

export type LogAuditEventMutationVariables = Exact<{
  action: string;
  tableName: string;
  recordId?: string | null | undefined;
  details?: unknown;
}>;


export type LogAuditEventMutation = { logAuditEvent: string | null };

export type CurrentStaffQueryVariables = Exact<{
  staffId: string;
}>;


export type CurrentStaffQuery = { staffCollection: { edges: Array<{ node: { id: string, fullName: string, isActive: boolean, staffRolesCollection: { edges: Array<{ node: { role: AppRole } }> } | null } }> } };


export const LogAuditEventDocument = {"kind":"Document","definitions":[{"kind":"OperationDefinition","operation":"mutation","name":{"kind":"Name","value":"LogAuditEvent"},"variableDefinitions":[{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"action"}},"type":{"kind":"NonNullType","type":{"kind":"NamedType","name":{"kind":"Name","value":"String"}}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"tableName"}},"type":{"kind":"NonNullType","type":{"kind":"NamedType","name":{"kind":"Name","value":"String"}}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"recordId"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"UUID"}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"details"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"JSON"}}}],"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"logAuditEvent"},"arguments":[{"kind":"Argument","name":{"kind":"Name","value":"pAction"},"value":{"kind":"Variable","name":{"kind":"Name","value":"action"}}},{"kind":"Argument","name":{"kind":"Name","value":"pTableName"},"value":{"kind":"Variable","name":{"kind":"Name","value":"tableName"}}},{"kind":"Argument","name":{"kind":"Name","value":"pRecordId"},"value":{"kind":"Variable","name":{"kind":"Name","value":"recordId"}}},{"kind":"Argument","name":{"kind":"Name","value":"pDetails"},"value":{"kind":"Variable","name":{"kind":"Name","value":"details"}}}]}]}}]} as unknown as DocumentNode<LogAuditEventMutation, LogAuditEventMutationVariables>;
export const CurrentStaffDocument = {"kind":"Document","definitions":[{"kind":"OperationDefinition","operation":"query","name":{"kind":"Name","value":"CurrentStaff"},"variableDefinitions":[{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"staffId"}},"type":{"kind":"NonNullType","type":{"kind":"NamedType","name":{"kind":"Name","value":"UUID"}}}}],"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"staffCollection"},"arguments":[{"kind":"Argument","name":{"kind":"Name","value":"filter"},"value":{"kind":"ObjectValue","fields":[{"kind":"ObjectField","name":{"kind":"Name","value":"id"},"value":{"kind":"ObjectValue","fields":[{"kind":"ObjectField","name":{"kind":"Name","value":"eq"},"value":{"kind":"Variable","name":{"kind":"Name","value":"staffId"}}}]}}]}},{"kind":"Argument","name":{"kind":"Name","value":"first"},"value":{"kind":"IntValue","value":"1"}}],"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"edges"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"node"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"fullName"}},{"kind":"Field","name":{"kind":"Name","value":"isActive"}},{"kind":"Field","name":{"kind":"Name","value":"staffRolesCollection"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"edges"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"node"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"role"}}]}}]}}]}}]}}]}}]}}]}}]} as unknown as DocumentNode<CurrentStaffQuery, CurrentStaffQueryVariables>;