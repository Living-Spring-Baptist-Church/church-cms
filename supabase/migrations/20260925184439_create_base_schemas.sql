-- Foundation for every later migration: extensions, internal schemas and the shared updated_at trigger.

create extension if not exists pg_graphql;
create extension if not exists pgtap with schema extensions;

comment on schema public is e'@graphql({"inflect_names": true})';

create schema if not exists private;
comment on schema private is 'Internal helpers for RLS and business functions. Never exposed to the API or to app roles.';

create schema if not exists audit;
comment on schema audit is 'The append-only change log, written only by the audit trigger. Never writable by app roles.';

revoke all on schema private from public, anon, authenticated;
revoke all on schema audit from public, anon, authenticated;

-- Postgres grants EXECUTE on new functions to PUBLIC by default; internal schemas must opt in instead.
alter default privileges in schema private revoke execute on functions from public;
alter default privileges in schema audit revoke execute on functions from public;

create function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

comment on function private.set_updated_at() is 'Before update trigger that stamps updated_at with the transaction time. Attach as <table>_updated_at.';

revoke execute on function private.set_updated_at() from public, anon, authenticated;
