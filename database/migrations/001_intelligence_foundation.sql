-- DRANEKA_INTELLIGENCE_SUPABASE_FOUNDATION_001
-- FOUNDATION-ONLY CANDIDATE.
-- Intended for isolated/non-production Supabase rehearsal until separately authorized.
-- This file does NOT create the full lifecycle table set and must not be treated as
-- production JI cutover authority.

begin;

-- Dedicated peer-domain roles. NOLOGIN keeps credential issuance/deployment separate
-- from database object definition. Runtime assumption mechanics are a later gate.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'intelligence_runtime') then
    create role intelligence_runtime nologin nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'intelligence_migrator') then
    create role intelligence_migrator nologin nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'intelligence_recovery_admin') then
    create role intelligence_recovery_admin nologin nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls;
  end if;
end
$$;

create schema if not exists intelligence;

revoke all on schema intelligence from public;
grant usage on schema intelligence to intelligence_runtime;
grant usage, create on schema intelligence to intelligence_migrator;
grant usage on schema intelligence to intelligence_recovery_admin;

comment on schema intelligence is
  'Draneka Intelligence peer-domain persistence boundary on the shared Draneka Supabase project.';

-- Domain-owned migration ledger. This is intentionally distinct from Journal public.schema_state
-- and from the transitional Neon journal_ji_schema_migrations table.
create table if not exists intelligence.schema_migrations (
  version integer primary key,
  contract_family text not null,
  source_lineage text,
  applied_at timestamptz not null default now(),
  constraint intelligence_schema_migrations_contract_nonempty
    check (btrim(contract_family) <> '')
);

comment on table intelligence.schema_migrations is
  'Append-only Draneka Intelligence schema lineage. Not Journal schema authority.';

alter table intelligence.schema_migrations enable row level security;

create or replace function intelligence.reject_immutable_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'Draneka Intelligence immutable record cannot be updated or deleted';
end
$$;

revoke all on function intelligence.reject_immutable_mutation() from public;
grant execute on function intelligence.reject_immutable_mutation() to intelligence_migrator;
grant execute on function intelligence.reject_immutable_mutation() to intelligence_recovery_admin;

-- Re-run safety for policy creation.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'intelligence'
      and tablename = 'schema_migrations'
      and policyname = 'intelligence_schema_migrations_runtime_select'
  ) then
    create policy intelligence_schema_migrations_runtime_select
      on intelligence.schema_migrations
      for select
      to intelligence_runtime
      using (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'intelligence'
      and tablename = 'schema_migrations'
      and policyname = 'intelligence_schema_migrations_migrator_select'
  ) then
    create policy intelligence_schema_migrations_migrator_select
      on intelligence.schema_migrations
      for select
      to intelligence_migrator
      using (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'intelligence'
      and tablename = 'schema_migrations'
      and policyname = 'intelligence_schema_migrations_migrator_insert'
  ) then
    create policy intelligence_schema_migrations_migrator_insert
      on intelligence.schema_migrations
      for insert
      to intelligence_migrator
      with check (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'intelligence'
      and tablename = 'schema_migrations'
      and policyname = 'intelligence_schema_migrations_recovery_select'
  ) then
    create policy intelligence_schema_migrations_recovery_select
      on intelligence.schema_migrations
      for select
      to intelligence_recovery_admin
      using (true);
  end if;
end
$$;

-- Append-only even if a future grant broadens accidentally.
do $$
begin
  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where not t.tgisinternal
      and n.nspname = 'intelligence'
      and c.relname = 'schema_migrations'
      and t.tgname = 'intelligence_schema_migrations_immutable'
  ) then
    create trigger intelligence_schema_migrations_immutable
      before update or delete on intelligence.schema_migrations
      for each row execute function intelligence.reject_immutable_mutation();
  end if;
end
$$;

revoke all on intelligence.schema_migrations from public;
grant select on intelligence.schema_migrations to intelligence_runtime;
grant select, insert on intelligence.schema_migrations to intelligence_migrator;
grant select on intelligence.schema_migrations to intelligence_recovery_admin;

-- Explicitly prevent Journal runtime from becoming Intelligence authority merely because
-- both domains share the physical database. Dynamic SQL avoids resolving an absent role
-- in qualification targets before the existence guard has run.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'journal_runtime') then
    execute 'revoke all on schema intelligence from journal_runtime';
    execute 'revoke all on intelligence.schema_migrations from journal_runtime';
  end if;
end
$$;

-- Same for Supabase end-user roles. These checks keep the script usable in isolated
-- PostgreSQL rehearsals where the roles may not exist.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on schema intelligence from anon';
    execute 'revoke all on intelligence.schema_migrations from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on schema intelligence from authenticated';
    execute 'revoke all on intelligence.schema_migrations from authenticated';
  end if;
end
$$;

-- Fail closed if version 1 already exists with a different identity.
do $$
declare
  existing_contract text;
  existing_lineage text;
begin
  select contract_family, source_lineage
    into existing_contract, existing_lineage
  from intelligence.schema_migrations
  where version = 1;

  if found then
    if existing_contract is distinct from 'DRANEKA_INTELLIGENCE_SUPABASE_FOUNDATION_001'
       or existing_lineage is distinct from 'TRANSITIONAL_JI_NEON_17_23' then
      raise exception 'Intelligence foundation migration version 1 identity mismatch';
    end if;
  else
    insert into intelligence.schema_migrations(version, contract_family, source_lineage)
    values (1, 'DRANEKA_INTELLIGENCE_SUPABASE_FOUNDATION_001', 'TRANSITIONAL_JI_NEON_17_23');
  end if;
end
$$;

commit;
