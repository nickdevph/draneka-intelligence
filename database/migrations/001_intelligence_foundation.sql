-- DRANEKA_INTELLIGENCE_SUPABASE_FOUNDATION_001
-- FOUNDATION-ONLY CANDIDATE.
-- Intended for isolated/non-production Supabase rehearsal until separately authorized.
-- This file does NOT create the full lifecycle table set and must not be treated as
-- production JI cutover authority.

begin;

-- Dedicated peer-domain roles. Existing roles are accepted only if they exactly match
-- the foundation contract. No role memberships are authorized by this foundation.
do $$
declare
  expected_role text;
  r record;
begin
  foreach expected_role in array array[
    'intelligence_runtime',
    'intelligence_migrator',
    'intelligence_recovery_admin'
  ]
  loop
    select *
      into r
    from pg_roles
    where rolname = expected_role;

    if not found then
      execute format(
        'create role %I nologin nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls',
        expected_role
      );
    else
      if r.rolcanlogin
         or r.rolsuper
         or r.rolcreatedb
         or r.rolcreaterole
         or r.rolinherit
         or r.rolreplication
         or r.rolbypassrls then
        raise exception 'Existing role % violates Draneka Intelligence foundation attributes', expected_role;
      end if;
    end if;
  end loop;

  if exists (
    select 1
    from pg_auth_members m
    join pg_roles granted_role on granted_role.oid = m.roleid
    join pg_roles member_role on member_role.oid = m.member
    where granted_role.rolname = any (array[
            'intelligence_runtime',
            'intelligence_migrator',
            'intelligence_recovery_admin'
          ])
       or member_role.rolname = any (array[
            'intelligence_runtime',
            'intelligence_migrator',
            'intelligence_recovery_admin'
          ])
  ) then
    raise exception 'Unexpected role membership involving intelligence_* role';
  end if;
end
$$;

-- intelligence_migrator is the canonical schema/object owner and the only future
-- Intelligence migration object-creator role. If the namespace already exists with a
-- different owner, stop rather than normalizing unknown ownership.
do $$
declare
  existing_owner text;
begin
  select owner_role.rolname
    into existing_owner
  from pg_namespace n
  join pg_roles owner_role on owner_role.oid = n.nspowner
  where n.nspname = 'intelligence';

  if not found then
    execute 'create schema intelligence authorization intelligence_migrator';
  elsif existing_owner <> 'intelligence_migrator' then
    raise exception 'Existing intelligence schema owner mismatch: %', existing_owner;
  end if;
end
$$;

-- Reject unknown schema ACL holders before converging the known allow/deny set.
do $$
begin
  if exists (
    select 1
    from pg_namespace n
    cross join lateral aclexplode(coalesce(n.nspacl, acldefault('n', n.nspowner))) acl
    left join pg_roles grantee_role on grantee_role.oid = acl.grantee
    where n.nspname = 'intelligence'
      and coalesce(grantee_role.rolname, 'PUBLIC') not in (
        'PUBLIC',
        'intelligence_runtime',
        'intelligence_migrator',
        'intelligence_recovery_admin',
        'journal_runtime',
        'anon',
        'authenticated'
      )
  ) then
    raise exception 'Unexpected ACL holder on intelligence schema';
  end if;
end
$$;

revoke all on schema intelligence from public;
revoke all on schema intelligence from intelligence_runtime;
revoke all on schema intelligence from intelligence_migrator;
revoke all on schema intelligence from intelligence_recovery_admin;
grant usage on schema intelligence to intelligence_runtime;
grant usage, create on schema intelligence to intelligence_migrator;
grant usage on schema intelligence to intelligence_recovery_admin;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'journal_runtime') then
    execute 'revoke all on schema intelligence from journal_runtime';
  end if;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on schema intelligence from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on schema intelligence from authenticated';
  end if;
end
$$;

do $$
begin
  if not has_schema_privilege('intelligence_runtime', 'intelligence', 'USAGE')
     or has_schema_privilege('intelligence_runtime', 'intelligence', 'CREATE')
     or not has_schema_privilege('intelligence_migrator', 'intelligence', 'USAGE')
     or not has_schema_privilege('intelligence_migrator', 'intelligence', 'CREATE')
     or not has_schema_privilege('intelligence_recovery_admin', 'intelligence', 'USAGE')
     or has_schema_privilege('intelligence_recovery_admin', 'intelligence', 'CREATE') then
    raise exception 'Intelligence schema privilege contract mismatch';
  end if;

  if exists (
    select 1
    from pg_namespace n
    cross join lateral aclexplode(coalesce(n.nspacl, acldefault('n', n.nspowner))) acl
    where n.nspname = 'intelligence'
      and acl.grantee = 0
  ) then
    raise exception 'PUBLIC retains privilege on intelligence schema';
  end if;
end
$$;

comment on schema intelligence is
  'Draneka Intelligence peer-domain persistence boundary on the shared Draneka Supabase project.';

-- Existing Intelligence namespaces are accepted only when their object inventory is
-- exactly the foundation-owned set. Unknown relations, types or functions fail closed
-- before any grants or ledger state can be certified.
do $$
begin
  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'intelligence'
      and c.relname not in ('schema_migrations', 'schema_migrations_pkey')
  ) then
    raise exception 'Unexpected relation in intelligence schema';
  end if;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'intelligence'
      and not (
        p.proname = 'reject_immutable_mutation'
        and pg_get_function_identity_arguments(p.oid) = ''
      )
  ) then
    raise exception 'Unexpected function in intelligence schema';
  end if;

  if exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'intelligence'
      and t.typname not in ('schema_migrations', '_schema_migrations')
  ) then
    raise exception 'Unexpected type in intelligence schema';
  end if;
end
$$;

-- Fail closed if an existing migration ledger has incompatible type/owner/shape.
do $$
declare
  existing_kind text;
  existing_owner text;
  ledger_oid oid;
  default_expr text;
begin
  select c.oid, c.relkind, owner_role.rolname
    into ledger_oid, existing_kind, existing_owner
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  join pg_roles owner_role on owner_role.oid = c.relowner
  where n.nspname = 'intelligence'
    and c.relname = 'schema_migrations';

  if not found then
    execute $ddl$
      create table intelligence.schema_migrations (
        version integer primary key,
        contract_family text not null,
        source_lineage text,
        applied_at timestamptz not null default now(),
        constraint intelligence_schema_migrations_contract_nonempty
          check (btrim(contract_family) <> '')
      )
    $ddl$;
    execute 'alter table intelligence.schema_migrations owner to intelligence_migrator';

    select c.oid
      into ledger_oid
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'intelligence'
      and c.relname = 'schema_migrations';
  else
    if existing_kind <> 'r' then
      raise exception 'intelligence.schema_migrations exists but is not a table';
    end if;
    if existing_owner <> 'intelligence_migrator' then
      raise exception 'Existing schema_migrations owner mismatch: %', existing_owner;
    end if;
  end if;

  if (
    select count(*)
    from pg_attribute a
    where a.attrelid = ledger_oid
      and a.attnum > 0
      and not a.attisdropped
  ) <> 4 then
    raise exception 'schema_migrations column count mismatch';
  end if;

  if not exists (
    select 1
    from pg_attribute a
    left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
    where a.attrelid = ledger_oid
      and a.attnum = 1
      and a.attname = 'version'
      and a.atttypid = 'integer'::regtype
      and a.attnotnull
      and d.oid is null
  ) then
    raise exception 'schema_migrations.version definition mismatch';
  end if;

  if not exists (
    select 1
    from pg_attribute a
    left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
    where a.attrelid = ledger_oid
      and a.attnum = 2
      and a.attname = 'contract_family'
      and a.atttypid = 'text'::regtype
      and a.attnotnull
      and d.oid is null
  ) then
    raise exception 'schema_migrations.contract_family definition mismatch';
  end if;

  if not exists (
    select 1
    from pg_attribute a
    left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
    where a.attrelid = ledger_oid
      and a.attnum = 3
      and a.attname = 'source_lineage'
      and a.atttypid = 'text'::regtype
      and not a.attnotnull
      and d.oid is null
  ) then
    raise exception 'schema_migrations.source_lineage definition mismatch';
  end if;

  select pg_get_expr(d.adbin, d.adrelid)
    into default_expr
  from pg_attribute a
  join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
  where a.attrelid = ledger_oid
    and a.attnum = 4
    and a.attname = 'applied_at'
    and a.atttypid = 'timestamp with time zone'::regtype
    and a.attnotnull;

  if default_expr is distinct from 'now()' then
    raise exception 'schema_migrations.applied_at definition mismatch';
  end if;

  if (
    select count(*)
    from pg_constraint con
    where con.conrelid = ledger_oid
      and con.contype in ('p', 'c', 'u', 'f', 'x')
  ) <> 2 then
    raise exception 'schema_migrations constraint set mismatch';
  end if;

  if not exists (
    select 1
    from pg_constraint con
    where con.conrelid = ledger_oid
      and con.contype = 'p'
      and con.conname = 'schema_migrations_pkey'
      and con.conkey = array[1]::smallint[]
      and con.convalidated
  ) then
    raise exception 'schema_migrations primary key mismatch';
  end if;

  if not exists (
    select 1
    from pg_constraint con
    where con.conrelid = ledger_oid
      and con.contype = 'c'
      and con.conname = 'intelligence_schema_migrations_contract_nonempty'
      and con.convalidated
      and regexp_replace(
            pg_get_expr(con.conbin, con.conrelid, true),
            '[[:space:]]+',
            '',
            'g'
          ) in (
            'btrim(contract_family)<>''''::text',
            '(btrim(contract_family)<>''''::text)'
          )
  ) then
    raise exception 'schema_migrations contract check mismatch';
  end if;
end
$$;

comment on table intelligence.schema_migrations is
  'Append-only Draneka Intelligence native migration ledger. Transitional Neon lineage is evidence only, not copied into native version numbering.';

alter table intelligence.schema_migrations enable row level security;
alter table intelligence.schema_migrations force row level security;

-- Canonical immutable guard function. Reject unexpected overloads, then converge the
-- no-argument trigger function. The function is owned by the migrator but PUBLIC receives
-- no execution path.
do $$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'intelligence'
      and p.proname = 'reject_immutable_mutation'
      and pg_get_function_identity_arguments(p.oid) <> ''
  ) then
    raise exception 'Unexpected overload of intelligence.reject_immutable_mutation';
  end if;
end
$$;

create or replace function intelligence.reject_immutable_mutation()
returns trigger
language plpgsql
volatile
security invoker
as $$
begin
  raise exception 'Draneka Intelligence immutable record cannot be updated or deleted';
end
$$;

alter function intelligence.reject_immutable_mutation() owner to intelligence_migrator;

do $$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
    left join pg_roles grantee_role on grantee_role.oid = acl.grantee
    where n.nspname = 'intelligence'
      and p.proname = 'reject_immutable_mutation'
      and pg_get_function_identity_arguments(p.oid) = ''
      and coalesce(grantee_role.rolname, 'PUBLIC') not in (
        'PUBLIC',
        'intelligence_migrator',
        'intelligence_recovery_admin',
        'intelligence_runtime'
      )
  ) then
    raise exception 'Unexpected ACL holder on reject_immutable_mutation()';
  end if;
end
$$;

revoke all on function intelligence.reject_immutable_mutation() from public;
revoke all on function intelligence.reject_immutable_mutation() from intelligence_runtime;
revoke all on function intelligence.reject_immutable_mutation() from intelligence_migrator;
revoke all on function intelligence.reject_immutable_mutation() from intelligence_recovery_admin;
grant execute on function intelligence.reject_immutable_mutation() to intelligence_migrator;
grant execute on function intelligence.reject_immutable_mutation() to intelligence_recovery_admin;

-- intelligence_migrator is the only canonical future object-creator role for this schema.
-- PostgreSQL composes per-schema defaults with the creator's global defaults, so a
-- per-schema REVOKE cannot safely cancel the built-in PUBLIC EXECUTE default. Because
-- intelligence_migrator is a dedicated Intelligence creator, revoke PUBLIC EXECUTE at
-- the creator-role global default and reject any schema-specific function default ACL.
do $$
begin
  if exists (
    select 1
    from pg_default_acl d
    join pg_roles owner_role on owner_role.oid = d.defaclrole
    cross join lateral aclexplode(d.defaclacl) acl
    left join pg_roles grantee_role on grantee_role.oid = acl.grantee
    where owner_role.rolname = 'intelligence_migrator'
      and d.defaclobjtype = 'f'
      and (
        d.defaclnamespace <> 0
        or coalesce(grantee_role.rolname, 'PUBLIC') not in (
          'PUBLIC',
          'intelligence_migrator'
        )
      )
  ) then
    raise exception 'Unexpected default function ACL state for intelligence_migrator';
  end if;
end
$$;

alter default privileges for role intelligence_migrator
  revoke execute on functions from public;

do $$
begin
  if not exists (
    select 1
    from pg_default_acl d
    join pg_roles owner_role on owner_role.oid = d.defaclrole
    where owner_role.rolname = 'intelligence_migrator'
      and d.defaclnamespace = 0
      and d.defaclobjtype = 'f'
  ) then
    raise exception 'Missing Intelligence creator default function privilege contract';
  end if;

  if exists (
    select 1
    from pg_default_acl d
    join pg_roles owner_role on owner_role.oid = d.defaclrole
    cross join lateral aclexplode(d.defaclacl) acl
    left join pg_roles grantee_role on grantee_role.oid = acl.grantee
    where owner_role.rolname = 'intelligence_migrator'
      and d.defaclobjtype = 'f'
      and (
        d.defaclnamespace <> 0
        or (acl.grantee = 0 and acl.privilege_type = 'EXECUTE')
        or coalesce(grantee_role.rolname, 'PUBLIC') not in ('intelligence_migrator')
      )
  ) then
    raise exception 'Unsafe default function privilege state for intelligence_migrator';
  end if;
end
$$;

-- Reject unknown policies. A single obsolete policy from the earlier foundation candidate
-- is explicitly recognized and removed; any other unexpected policy fails closed.
do $$
begin
  if exists (
    select 1
    from pg_policies
    where schemaname = 'intelligence'
      and tablename = 'schema_migrations'
      and policyname not in (
        'intelligence_schema_migrations_runtime_select',
        'intelligence_schema_migrations_migrator_select',
        'intelligence_schema_migrations_migrator_insert',
        'intelligence_schema_migrations_recovery_select',
        'intelligence_schema_migrations_migrator_all'
      )
  ) then
    raise exception 'Unexpected policy on intelligence.schema_migrations';
  end if;
end
$$;

drop policy if exists intelligence_schema_migrations_migrator_all
  on intelligence.schema_migrations;
drop policy if exists intelligence_schema_migrations_runtime_select
  on intelligence.schema_migrations;
drop policy if exists intelligence_schema_migrations_migrator_select
  on intelligence.schema_migrations;
drop policy if exists intelligence_schema_migrations_migrator_insert
  on intelligence.schema_migrations;
drop policy if exists intelligence_schema_migrations_recovery_select
  on intelligence.schema_migrations;

create policy intelligence_schema_migrations_runtime_select
  on intelligence.schema_migrations
  for select
  to intelligence_runtime
  using (true);

create policy intelligence_schema_migrations_migrator_select
  on intelligence.schema_migrations
  for select
  to intelligence_migrator
  using (true);

create policy intelligence_schema_migrations_migrator_insert
  on intelligence.schema_migrations
  for insert
  to intelligence_migrator
  with check (true);

create policy intelligence_schema_migrations_recovery_select
  on intelligence.schema_migrations
  for select
  to intelligence_recovery_admin
  using (true);

do $$
begin
  if (
    select count(*)
    from pg_policies
    where schemaname = 'intelligence'
      and tablename = 'schema_migrations'
  ) <> 4 then
    raise exception 'schema_migrations policy count mismatch';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'intelligence'
      and tablename = 'schema_migrations'
      and policyname = 'intelligence_schema_migrations_runtime_select'
      and permissive = 'PERMISSIVE'
      and roles = array['intelligence_runtime']::name[]
      and cmd = 'SELECT'
      and qual in ('true', '(true)')
      and with_check is null
  ) then
    raise exception 'runtime SELECT policy mismatch';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'intelligence'
      and tablename = 'schema_migrations'
      and policyname = 'intelligence_schema_migrations_migrator_select'
      and permissive = 'PERMISSIVE'
      and roles = array['intelligence_migrator']::name[]
      and cmd = 'SELECT'
      and qual in ('true', '(true)')
      and with_check is null
  ) then
    raise exception 'migrator SELECT policy mismatch';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'intelligence'
      and tablename = 'schema_migrations'
      and policyname = 'intelligence_schema_migrations_migrator_insert'
      and permissive = 'PERMISSIVE'
      and roles = array['intelligence_migrator']::name[]
      and cmd = 'INSERT'
      and qual is null
      and with_check in ('true', '(true)')
  ) then
    raise exception 'migrator INSERT policy mismatch';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'intelligence'
      and tablename = 'schema_migrations'
      and policyname = 'intelligence_schema_migrations_recovery_select'
      and permissive = 'PERMISSIVE'
      and roles = array['intelligence_recovery_admin']::name[]
      and cmd = 'SELECT'
      and qual in ('true', '(true)')
      and with_check is null
  ) then
    raise exception 'recovery SELECT policy mismatch';
  end if;
end
$$;

-- Reject unexpected non-internal triggers, then replace the canonical immutable trigger
-- so same-name drift cannot survive a rerun.
do $$
begin
  if exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where not t.tgisinternal
      and n.nspname = 'intelligence'
      and c.relname = 'schema_migrations'
      and t.tgname not in (
        'intelligence_schema_migrations_immutable',
        'intelligence_schema_migrations_truncate_guard'
      )
  ) then
    raise exception 'Unexpected non-internal trigger on intelligence.schema_migrations';
  end if;
end
$$;

drop trigger if exists intelligence_schema_migrations_immutable
  on intelligence.schema_migrations;

create trigger intelligence_schema_migrations_immutable
  before update or delete on intelligence.schema_migrations
  for each row execute function intelligence.reject_immutable_mutation();

create trigger intelligence_schema_migrations_truncate_guard
  before truncate on intelligence.schema_migrations
  for each statement execute function intelligence.reject_immutable_mutation();

do $$
begin
  if (
    select count(*)
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where not t.tgisinternal
      and n.nspname = 'intelligence'
      and c.relname = 'schema_migrations'
  ) <> 2
  or not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where not t.tgisinternal
      and n.nspname = 'intelligence'
      and c.relname = 'schema_migrations'
      and t.tgname = 'intelligence_schema_migrations_immutable'
      and t.tgfoid = 'intelligence.reject_immutable_mutation()'::regprocedure
      and t.tgtype = 27
      and t.tgenabled = 'O'
  )
  or not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where not t.tgisinternal
      and n.nspname = 'intelligence'
      and c.relname = 'schema_migrations'
      and t.tgname = 'intelligence_schema_migrations_truncate_guard'
      and t.tgfoid = 'intelligence.reject_immutable_mutation()'::regprocedure
      and t.tgtype = 34
      and t.tgenabled = 'O'
  ) then
    raise exception 'Immutable trigger contract mismatch';
  end if;
end
$$;

-- Reject rewrite rules that could suppress or redirect the native ledger insert.
do $$
begin
  if exists (
    select 1
    from pg_rewrite rw
    where rw.ev_class = 'intelligence.schema_migrations'::regclass
  ) then
    raise exception 'Unexpected rewrite rule on intelligence.schema_migrations';
  end if;
end
$$;

-- Reject column-level ACL drift. The foundation contract has no column grants.
do $$
begin
  if exists (
    select 1
    from pg_attribute a
    join pg_class c on c.oid = a.attrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'intelligence'
      and c.relname = 'schema_migrations'
      and a.attnum > 0
      and not a.attisdropped
      and a.attacl is not null
  ) then
    raise exception 'Unexpected column-level ACL on intelligence.schema_migrations';
  end if;
end
$$;

-- Reject unknown table ACL holders before converging grants.
do $$
begin
  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl
    left join pg_roles grantee_role on grantee_role.oid = acl.grantee
    where n.nspname = 'intelligence'
      and c.relname = 'schema_migrations'
      and coalesce(grantee_role.rolname, 'PUBLIC') not in (
        'PUBLIC',
        'intelligence_runtime',
        'intelligence_migrator',
        'intelligence_recovery_admin',
        'journal_runtime',
        'anon',
        'authenticated'
      )
  ) then
    raise exception 'Unexpected ACL holder on intelligence.schema_migrations';
  end if;
end
$$;

revoke all on intelligence.schema_migrations from public;
revoke all on intelligence.schema_migrations from intelligence_runtime;
revoke all on intelligence.schema_migrations from intelligence_migrator;
revoke all on intelligence.schema_migrations from intelligence_recovery_admin;

grant select on intelligence.schema_migrations to intelligence_runtime;
grant select, insert on intelligence.schema_migrations to intelligence_migrator;
grant select on intelligence.schema_migrations to intelligence_recovery_admin;

-- Explicitly prevent Journal runtime and Supabase end-user roles from receiving direct
-- Intelligence foundation access. Dynamic SQL keeps isolated PostgreSQL rehearsal usable
-- when those roles do not exist.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'journal_runtime') then
    execute 'revoke all on intelligence.schema_migrations from journal_runtime';
  end if;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on intelligence.schema_migrations from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on intelligence.schema_migrations from authenticated';
  end if;
end
$$;

do $$
declare
  ledger_oid oid := 'intelligence.schema_migrations'::regclass;
begin
  if exists (
    select 1
    from pg_class c
    cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl
    left join pg_roles grantee_role on grantee_role.oid = acl.grantee
    where c.oid = ledger_oid
      and (
        (coalesce(grantee_role.rolname, 'PUBLIC') = 'PUBLIC')
        or (grantee_role.rolname = 'intelligence_runtime' and acl.privilege_type <> 'SELECT')
        or (grantee_role.rolname = 'intelligence_migrator' and acl.privilege_type not in ('SELECT', 'INSERT'))
        or (grantee_role.rolname = 'intelligence_recovery_admin' and acl.privilege_type <> 'SELECT')
        or coalesce(grantee_role.rolname, 'PUBLIC') not in (
          'PUBLIC',
          'intelligence_runtime',
          'intelligence_migrator',
          'intelligence_recovery_admin'
        )
      )
  ) then
    raise exception 'schema_migrations ACL contains privilege outside the allowlist';
  end if;

  if not exists (
    select 1
    from pg_class c
    cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl
    join pg_roles grantee_role on grantee_role.oid = acl.grantee
    where c.oid = ledger_oid
      and grantee_role.rolname = 'intelligence_runtime'
      and acl.privilege_type = 'SELECT'
  ) or not exists (
    select 1
    from pg_class c
    cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl
    join pg_roles grantee_role on grantee_role.oid = acl.grantee
    where c.oid = ledger_oid
      and grantee_role.rolname = 'intelligence_migrator'
      and acl.privilege_type = 'SELECT'
  ) or not exists (
    select 1
    from pg_class c
    cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl
    join pg_roles grantee_role on grantee_role.oid = acl.grantee
    where c.oid = ledger_oid
      and grantee_role.rolname = 'intelligence_migrator'
      and acl.privilege_type = 'INSERT'
  ) or not exists (
    select 1
    from pg_class c
    cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl
    join pg_roles grantee_role on grantee_role.oid = acl.grantee
    where c.oid = ledger_oid
      and grantee_role.rolname = 'intelligence_recovery_admin'
      and acl.privilege_type = 'SELECT'
  ) then
    raise exception 'schema_migrations ACL is missing required grants';
  end if;
end
$$;

-- Final exact RLS state check before recording the foundation identity.
do $$
begin
  if not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'intelligence'
      and c.relname = 'schema_migrations'
      and c.relrowsecurity
      and c.relforcerowsecurity
  ) then
    raise exception 'schema_migrations RLS/FORCE RLS state mismatch';
  end if;
end
$$;

-- Fail closed if native target migration version 1 already exists with a different
-- identity. Transitional Neon versions 17-23 are evidence only via source_lineage and
-- are never inserted into this native target version namespace.
do $$
declare
  existing_contract text;
  existing_lineage text;
  inserted_version integer;
begin
  if exists (
    select 1
    from intelligence.schema_migrations
    where version <> 1
  ) then
    raise exception 'Unexpected native Intelligence migration version';
  end if;

  if (select count(*) from intelligence.schema_migrations) > 1 then
    raise exception 'Unexpected additional native Intelligence migration ledger rows';
  end if;

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
    values (1, 'DRANEKA_INTELLIGENCE_SUPABASE_FOUNDATION_001', 'TRANSITIONAL_JI_NEON_17_23')
    returning version into inserted_version;

    if not found or inserted_version is distinct from 1 then
      raise exception 'Intelligence foundation migration identity insert was suppressed or altered';
    end if;
  end if;

  if (select count(*) from intelligence.schema_migrations) <> 1
     or not exists (
       select 1
       from intelligence.schema_migrations
       where version = 1
         and contract_family = 'DRANEKA_INTELLIGENCE_SUPABASE_FOUNDATION_001'
         and source_lineage = 'TRANSITIONAL_JI_NEON_17_23'
     ) then
    raise exception 'Intelligence foundation migration identity was not recorded exactly';
  end if;
end
$$;

commit;
