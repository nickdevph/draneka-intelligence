-- DRANEKA_INTELLIGENCE_SUPABASE_FOUNDATION_001 verification
-- Read-only exact-contract verification for isolated/non-production rehearsal.

begin;
set transaction read only;

-- 1. Role attributes and membership graph.
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

select
  granted_role.rolname as granted_role,
  member_role.rolname as member_role,
  m.admin_option
from pg_auth_members m
join pg_roles granted_role on granted_role.oid = m.roleid
join pg_roles member_role on member_role.oid = m.member
where granted_role.rolname in (
        'intelligence_runtime',
        'intelligence_migrator',
        'intelligence_recovery_admin'
      )
   or member_role.rolname in (
        'intelligence_runtime',
        'intelligence_migrator',
        'intelligence_recovery_admin'
      )
order by granted_role.rolname, member_role.rolname;

-- 2. Namespace owner and exact ACL readback.
select
  n.nspname as schema_name,
  owner_role.rolname as owner_role
from pg_namespace n
join pg_roles owner_role on owner_role.oid = n.nspowner
where n.nspname = 'intelligence';

select
  coalesce(grantee_role.rolname, 'PUBLIC') as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_namespace n
cross join lateral aclexplode(coalesce(n.nspacl, acldefault('n', n.nspowner))) acl
left join pg_roles grantee_role on grantee_role.oid = acl.grantee
where n.nspname = 'intelligence'
order by grantee, acl.privilege_type;

-- 3. Native migration ledger structure, ownership, RLS and constraints.
select
  c.oid::regclass as relation,
  owner_role.rolname as owner_role,
  c.relkind,
  c.relrowsecurity as rls_enabled,
  c.relforcerowsecurity as force_rls
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
join pg_roles owner_role on owner_role.oid = c.relowner
where n.nspname = 'intelligence'
  and c.relname = 'schema_migrations';

select
  a.attnum,
  a.attname,
  format_type(a.atttypid, a.atttypmod) as data_type,
  a.attnotnull,
  pg_get_expr(d.adbin, d.adrelid) as default_expr
from pg_attribute a
left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
where a.attrelid = 'intelligence.schema_migrations'::regclass
  and a.attnum > 0
  and not a.attisdropped
order by a.attnum;

select
  con.conname,
  con.contype,
  con.convalidated,
  con.conkey,
  pg_get_constraintdef(con.oid, true) as definition
from pg_constraint con
where con.conrelid = 'intelligence.schema_migrations'::regclass
  and con.contype in ('p', 'c', 'u', 'f', 'x')
order by con.conname;

-- 4. Exact policy set.
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
  and tablename = 'schema_migrations'
order by policyname;

-- 5. Exact immutable trigger and function security.
select
  t.tgname,
  t.tgtype,
  t.tgenabled,
  t.tgfoid::regprocedure as function_identity,
  pg_get_triggerdef(t.oid, true) as trigger_definition
from pg_trigger t
where t.tgrelid = 'intelligence.schema_migrations'::regclass
  and not t.tgisinternal
order by t.tgname;

select
  p.oid::regprocedure as function_identity,
  owner_role.rolname as owner_role,
  l.lanname as language_name,
  p.prosecdef as security_definer,
  p.provolatile
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
join pg_roles owner_role on owner_role.oid = p.proowner
join pg_language l on l.oid = p.prolang
where n.nspname = 'intelligence'
  and p.proname = 'reject_immutable_mutation'
  and pg_get_function_identity_arguments(p.oid) = '';

select
  coalesce(grantee_role.rolname, 'PUBLIC') as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
left join pg_roles grantee_role on grantee_role.oid = acl.grantee
where n.nspname = 'intelligence'
  and p.proname = 'reject_immutable_mutation'
  and pg_get_function_identity_arguments(p.oid) = ''
order by grantee, acl.privilege_type;

-- 6. Default function privileges for the canonical future object creator.
select
  owner_role.rolname as creator_role,
  case when d.defaclnamespace = 0 then '<GLOBAL>' else n.nspname end as default_scope,
  d.defaclobjtype,
  coalesce(grantee_role.rolname, 'PUBLIC') as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_default_acl d
join pg_roles owner_role on owner_role.oid = d.defaclrole
left join pg_namespace n on n.oid = d.defaclnamespace
cross join lateral aclexplode(d.defaclacl) acl
left join pg_roles grantee_role on grantee_role.oid = acl.grantee
where owner_role.rolname = 'intelligence_migrator'
  and d.defaclobjtype = 'f'
order by default_scope, grantee, acl.privilege_type;

-- 7. Column-level ACL readback: the foundation contract grants no columns directly.
select
  a.attnum,
  a.attname,
  a.attacl
from pg_attribute a
where a.attrelid = 'intelligence.schema_migrations'::regclass
  and a.attnum > 0
  and not a.attisdropped
order by a.attnum;

-- 8. Ledger grants.
select
  coalesce(grantee_role.rolname, 'PUBLIC') as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl
left join pg_roles grantee_role on grantee_role.oid = acl.grantee
where n.nspname = 'intelligence'
  and c.relname = 'schema_migrations'
order by grantee, acl.privilege_type;

-- 9. Native migration identity. Source lineage is evidence only.
select version, contract_family, source_lineage, applied_at
from intelligence.schema_migrations
order by version;

-- 10. Cross-domain/end-user direct-access negative readback.
select
  r.rolname,
  has_schema_privilege(r.rolname, 'intelligence', 'USAGE') as has_schema_usage,
  has_schema_privilege(r.rolname, 'intelligence', 'CREATE') as has_schema_create,
  has_table_privilege(
    r.rolname,
    'intelligence.schema_migrations',
    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
  ) as has_any_ledger_privilege
from pg_roles r
where r.rolname in ('journal_runtime', 'anon', 'authenticated')
order by r.rolname;

-- 11. Exact-contract assertions. Any mismatch aborts qualification.
do $$
declare
  ledger_oid oid := 'intelligence.schema_migrations'::regclass;
  ledger_owner text;
  default_expr text;
begin
  if (
    select count(*)
    from pg_roles
    where rolname in (
      'intelligence_runtime',
      'intelligence_migrator',
      'intelligence_recovery_admin'
    )
      and not rolcanlogin
      and not rolsuper
      and not rolcreatedb
      and not rolcreaterole
      and not rolinherit
      and not rolreplication
      and not rolbypassrls
  ) <> 3 then
    raise exception 'FAIL: intelligence_* role attribute contract';
  end if;

  if exists (
    select 1
    from pg_auth_members m
    join pg_roles granted_role on granted_role.oid = m.roleid
    join pg_roles member_role on member_role.oid = m.member
    where granted_role.rolname in (
            'intelligence_runtime',
            'intelligence_migrator',
            'intelligence_recovery_admin'
          )
       or member_role.rolname in (
            'intelligence_runtime',
            'intelligence_migrator',
            'intelligence_recovery_admin'
          )
  ) then
    raise exception 'FAIL: unexpected intelligence_* role membership';
  end if;

  if not exists (
    select 1
    from pg_namespace n
    join pg_roles owner_role on owner_role.oid = n.nspowner
    where n.nspname = 'intelligence'
      and owner_role.rolname = 'intelligence_migrator'
  ) then
    raise exception 'FAIL: intelligence schema owner';
  end if;

  if not has_schema_privilege('intelligence_runtime', 'intelligence', 'USAGE')
     or has_schema_privilege('intelligence_runtime', 'intelligence', 'CREATE')
     or not has_schema_privilege('intelligence_migrator', 'intelligence', 'USAGE')
     or not has_schema_privilege('intelligence_migrator', 'intelligence', 'CREATE')
     or not has_schema_privilege('intelligence_recovery_admin', 'intelligence', 'USAGE')
     or has_schema_privilege('intelligence_recovery_admin', 'intelligence', 'CREATE') then
    raise exception 'FAIL: intelligence schema privilege allowlist';
  end if;

  if exists (
    select 1
    from pg_namespace n
    cross join lateral aclexplode(coalesce(n.nspacl, acldefault('n', n.nspowner))) acl
    left join pg_roles grantee_role on grantee_role.oid = acl.grantee
    where n.nspname = 'intelligence'
      and (
        acl.grantee = 0
        or coalesce(grantee_role.rolname, 'PUBLIC') not in (
          'intelligence_runtime',
          'intelligence_migrator',
          'intelligence_recovery_admin'
        )
        or (grantee_role.rolname = 'intelligence_runtime' and (acl.privilege_type <> 'USAGE' or acl.is_grantable))
        or (grantee_role.rolname = 'intelligence_recovery_admin' and (acl.privilege_type <> 'USAGE' or acl.is_grantable))
        or (grantee_role.rolname = 'intelligence_migrator' and acl.privilege_type not in ('USAGE', 'CREATE'))
      )
  ) then
    raise exception 'FAIL: intelligence schema ACL exactness';
  end if;

  select owner_role.rolname
    into ledger_owner
  from pg_class c
  join pg_roles owner_role on owner_role.oid = c.relowner
  where c.oid = ledger_oid
    and c.relkind = 'r'
    and c.relrowsecurity
    and c.relforcerowsecurity;

  if ledger_owner is distinct from 'intelligence_migrator' then
    raise exception 'FAIL: schema_migrations owner/RLS contract';
  end if;

  if (
    select count(*)
    from pg_attribute a
    where a.attrelid = ledger_oid
      and a.attnum > 0
      and not a.attisdropped
  ) <> 4 then
    raise exception 'FAIL: schema_migrations column count';
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
  ) or not exists (
    select 1
    from pg_attribute a
    left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
    where a.attrelid = ledger_oid
      and a.attnum = 2
      and a.attname = 'contract_family'
      and a.atttypid = 'text'::regtype
      and a.attnotnull
      and d.oid is null
  ) or not exists (
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
    raise exception 'FAIL: schema_migrations column definitions';
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
    raise exception 'FAIL: schema_migrations.applied_at default';
  end if;

  if (
    select count(*)
    from pg_constraint con
    where con.conrelid = ledger_oid
      and con.contype in ('p', 'c', 'u', 'f', 'x')
  ) <> 2
  or not exists (
    select 1
    from pg_constraint con
    where con.conrelid = ledger_oid
      and con.contype = 'p'
      and con.conname = 'schema_migrations_pkey'
      and con.conkey = array[1]::smallint[]
      and con.convalidated
  )
  or not exists (
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
    raise exception 'FAIL: schema_migrations constraints';
  end if;

  if (
    select count(*)
    from pg_policies
    where schemaname = 'intelligence'
      and tablename = 'schema_migrations'
  ) <> 4 then
    raise exception 'FAIL: schema_migrations policy count';
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
  )
  or not exists (
    select 1 from pg_policies
    where schemaname = 'intelligence'
      and tablename = 'schema_migrations'
      and policyname = 'intelligence_schema_migrations_migrator_select'
      and permissive = 'PERMISSIVE'
      and roles = array['intelligence_migrator']::name[]
      and cmd = 'SELECT'
      and qual in ('true', '(true)')
      and with_check is null
  )
  or not exists (
    select 1 from pg_policies
    where schemaname = 'intelligence'
      and tablename = 'schema_migrations'
      and policyname = 'intelligence_schema_migrations_migrator_insert'
      and permissive = 'PERMISSIVE'
      and roles = array['intelligence_migrator']::name[]
      and cmd = 'INSERT'
      and qual is null
      and with_check in ('true', '(true)')
  )
  or not exists (
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
    raise exception 'FAIL: schema_migrations policy definitions';
  end if;

  if (
    select count(*)
    from pg_trigger t
    where t.tgrelid = ledger_oid
      and not t.tgisinternal
  ) <> 1
  or not exists (
    select 1
    from pg_trigger t
    where t.tgrelid = ledger_oid
      and not t.tgisinternal
      and t.tgname = 'intelligence_schema_migrations_immutable'
      and t.tgfoid = 'intelligence.reject_immutable_mutation()'::regprocedure
      and t.tgtype = 27
      and t.tgenabled = 'O'
  ) then
    raise exception 'FAIL: immutable trigger exactness';
  end if;

  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_roles owner_role on owner_role.oid = p.proowner
    join pg_language l on l.oid = p.prolang
    where n.nspname = 'intelligence'
      and p.proname = 'reject_immutable_mutation'
      and pg_get_function_identity_arguments(p.oid) = ''
      and owner_role.rolname = 'intelligence_migrator'
      and l.lanname = 'plpgsql'
      and not p.prosecdef
      and p.provolatile = 'v'
  ) then
    raise exception 'FAIL: immutable function identity/security';
  end if;

  if has_function_privilege('intelligence_runtime', 'intelligence.reject_immutable_mutation()', 'EXECUTE') then
    raise exception 'FAIL: runtime can execute immutable guard function directly';
  end if;

  if not has_function_privilege('intelligence_recovery_admin', 'intelligence.reject_immutable_mutation()', 'EXECUTE') then
    raise exception 'FAIL: recovery admin missing immutable guard EXECUTE';
  end if;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
    where n.nspname = 'intelligence'
      and p.proname = 'reject_immutable_mutation'
      and pg_get_function_identity_arguments(p.oid) = ''
      and acl.grantee = 0
      and acl.privilege_type = 'EXECUTE'
  ) then
    raise exception 'FAIL: PUBLIC can execute immutable guard function';
  end if;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
    left join pg_roles grantee_role on grantee_role.oid = acl.grantee
    where n.nspname = 'intelligence'
      and p.proname = 'reject_immutable_mutation'
      and pg_get_function_identity_arguments(p.oid) = ''
      and (
        coalesce(grantee_role.rolname, 'PUBLIC') not in (
          'intelligence_migrator',
          'intelligence_recovery_admin'
        )
        or (grantee_role.rolname = 'intelligence_recovery_admin' and
            (acl.privilege_type <> 'EXECUTE' or acl.is_grantable))
        or (grantee_role.rolname = 'intelligence_migrator' and acl.privilege_type <> 'EXECUTE')
      )
  ) then
    raise exception 'FAIL: immutable guard function ACL exactness';
  end if;

  if not exists (
    select 1
    from pg_default_acl d
    join pg_roles owner_role on owner_role.oid = d.defaclrole
    where owner_role.rolname = 'intelligence_migrator'
      and d.defaclnamespace = 0
      and d.defaclobjtype = 'f'
  ) then
    raise exception 'FAIL: missing future-function default privilege contract';
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
    raise exception 'FAIL: future-function default privilege exactness';
  end if;

  if exists (
    select 1
    from pg_attribute a
    where a.attrelid = ledger_oid
      and a.attnum > 0
      and not a.attisdropped
      and a.attacl is not null
  ) then
    raise exception 'FAIL: schema_migrations column-level ACL exactness';
  end if;

  if exists (
    select 1
    from pg_class c
    cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl
    left join pg_roles grantee_role on grantee_role.oid = acl.grantee
    where c.oid = ledger_oid
      and (
        acl.grantee = 0
        or (grantee_role.rolname = 'intelligence_runtime' and (acl.privilege_type <> 'SELECT' or acl.is_grantable))
        or (grantee_role.rolname = 'intelligence_migrator' and acl.privilege_type not in ('SELECT', 'INSERT'))
        or (grantee_role.rolname = 'intelligence_recovery_admin' and (acl.privilege_type <> 'SELECT' or acl.is_grantable))
        or coalesce(grantee_role.rolname, 'PUBLIC') not in (
          'intelligence_runtime',
          'intelligence_migrator',
          'intelligence_recovery_admin'
        )
      )
  ) then
    raise exception 'FAIL: schema_migrations table ACL exactness';
  end if;

  if not exists (
    select 1
    from pg_class c
    cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl
    join pg_roles grantee_role on grantee_role.oid = acl.grantee
    where c.oid = ledger_oid
      and grantee_role.rolname = 'intelligence_runtime'
      and acl.privilege_type = 'SELECT'
  )
  or not exists (
    select 1
    from pg_class c
    cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl
    join pg_roles grantee_role on grantee_role.oid = acl.grantee
    where c.oid = ledger_oid
      and grantee_role.rolname = 'intelligence_migrator'
      and acl.privilege_type = 'SELECT'
  )
  or not exists (
    select 1
    from pg_class c
    cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl
    join pg_roles grantee_role on grantee_role.oid = acl.grantee
    where c.oid = ledger_oid
      and grantee_role.rolname = 'intelligence_migrator'
      and acl.privilege_type = 'INSERT'
  )
  or not exists (
    select 1
    from pg_class c
    cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl
    join pg_roles grantee_role on grantee_role.oid = acl.grantee
    where c.oid = ledger_oid
      and grantee_role.rolname = 'intelligence_recovery_admin'
      and acl.privilege_type = 'SELECT'
  ) then
    raise exception 'FAIL: schema_migrations required table grants';
  end if;

  if exists (
    select 1
    from pg_rewrite rw
    where rw.ev_class = ledger_oid
  ) then
    raise exception 'FAIL: unexpected schema_migrations rewrite rule';
  end if;

  if (select count(*) from intelligence.schema_migrations) <> 1
  or not exists (
    select 1
    from intelligence.schema_migrations
    where version = 1
      and contract_family = 'DRANEKA_INTELLIGENCE_SUPABASE_FOUNDATION_001'
      and source_lineage = 'TRANSITIONAL_JI_NEON_17_23'
  ) then
    raise exception 'FAIL: native foundation migration identity/source-lineage separation';
  end if;

  if exists (
    select 1
    from pg_roles r
    where r.rolname in ('journal_runtime', 'anon', 'authenticated')
      and (
        has_schema_privilege(r.rolname, 'intelligence', 'USAGE')
        or has_schema_privilege(r.rolname, 'intelligence', 'CREATE')
        or has_table_privilege(
          r.rolname,
          'intelligence.schema_migrations',
          'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
        )
      )
  ) then
    raise exception 'FAIL: peer/end-user role has direct Intelligence foundation access';
  end if;
end
$$;

select 'PASS' as intelligence_foundation_exact_contract;

rollback;
