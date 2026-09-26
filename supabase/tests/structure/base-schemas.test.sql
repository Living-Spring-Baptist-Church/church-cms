begin;

select plan(12);

select has_schema('private', 'should have the private schema for internal helpers');
select has_schema('audit', 'should have the audit schema for the change log');

select has_extension('extensions', 'pgtap', 'should have pgtap installed in the extensions schema');
select has_extension('pg_graphql', 'should have pg_graphql installed');

select is(
  obj_description('public'::regnamespace, 'pg_namespace'),
  '@graphql({"inflect_names": true})',
  'should turn on camelCase name inflection for the GraphQL API'
);

select schema_privs_are('private', 'anon', array[]::text[], 'should deny anon any access to the private schema');
select schema_privs_are('private', 'authenticated', array[]::text[], 'should deny authenticated any access to the private schema');
select schema_privs_are('audit', 'anon', array[]::text[], 'should deny anon any access to the audit schema');
select schema_privs_are('audit', 'authenticated', array[]::text[], 'should deny authenticated any access to the audit schema');

select function_returns('private', 'set_updated_at', array[]::text[], 'trigger', 'should expose set_updated_at as a trigger function');
select function_privs_are('private', 'set_updated_at', array[]::text[], 'authenticated', array[]::text[], 'should deny authenticated execute on set_updated_at');

create table pg_temp.updated_at_probes (
  id int primary key,
  label text not null,
  updated_at timestamptz not null
);

create trigger updated_at_probes_updated_at
  before update on pg_temp.updated_at_probes
  for each row execute function private.set_updated_at();

insert into pg_temp.updated_at_probes (id, label, updated_at) values (1, 'before', '2000-01-01T00:00:00Z');
update pg_temp.updated_at_probes set label = 'after' where id = 1;

select is(
  (select updated_at from pg_temp.updated_at_probes where id = 1),
  now(),
  'should set updated_at to the current transaction time on update'
);

select * from finish();

rollback;
