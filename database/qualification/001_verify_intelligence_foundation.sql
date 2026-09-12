-- DRANEKA_INTELLIGENCE_SUPABASE_FOUNDATION_001 verification
-- Read-only verification queries for isolated/non-production rehearsal.

-- 1. Namespace
select nspname as schema_name
from pg_namespace
where nspname = 'intelligence';

-- 2. Role attributes
select
  rolname,
  rolcanlogin,
  rolsuper,
  rolcreatedb,
  rolcreaterole,
  rolinherit,
  rolreplication,
  rolbypassrls
from pg_roles
where rolname in (
  'intelligence_runtime',
  'intelligence_migrator',
  'intelligence_recovery_admin'
)
order by rolname;

-- 3. Foundation ledger and RLS
select
  n.nspname as schema_name,
  c.relname as table_name,
  c.relrowsecurity as rls_enabled,
  c.relforcerowsecurity as force_rls
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'intelligence'
  and c.relname = 'schema_migrations';

select version, contract_family, source_lineage
from intelligence.schema_migrations
order by version;

-- 4. Policies
select
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
from pg_policies
where schemaname = 'intelligence'
order by tablename, policyname;

-- 5. Table grants
select grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'intelligence'
  and table_name = 'schema_migrations'
order by grantee, privilege_type;

-- 6. Schema grants
select
  r.rolname as role_name,
  has_schema_privilege(r.rolname, 'intelligence', 'USAGE') as has_usage,
  has_schema_privilege(r.rolname, 'intelligence', 'CREATE') as has_create
from pg_roles r
where r.rolname in (
  'intelligence_runtime',
  'intelligence_migrator',
  'intelligence_recovery_admin',
  'journal_runtime',
  'anon',
  'authenticated'
)
order by r.rolname;

-- 7. Cross-domain negative grant readback.
-- Expected: journal_runtime must have no privileges on Intelligence foundation objects.
select
  case
    when exists (select 1 from pg_roles where rolname = 'journal_runtime')
    then has_schema_privilege('journal_runtime', 'intelligence', 'USAGE')
    else false
  end as journal_runtime_has_intelligence_schema_usage,
  case
    when exists (select 1 from pg_roles where rolname = 'journal_runtime')
    then has_table_privilege('journal_runtime', 'intelligence.schema_migrations', 'SELECT,INSERT,UPDATE,DELETE')
    else false
  end as journal_runtime_has_intelligence_table_privilege;

-- 8. End-user direct-access negative readback.
select
  r.rolname,
  has_schema_privilege(r.rolname, 'intelligence', 'USAGE') as has_schema_usage,
  has_table_privilege(r.rolname, 'intelligence.schema_migrations', 'SELECT,INSERT,UPDATE,DELETE') as has_table_privilege
from pg_roles r
where r.rolname in ('anon', 'authenticated')
order by r.rolname;
