-- DRANEKA_INTELLIGENCE_SERVICE_IDENTITIES_001
-- Dedicated application/recovery identities for the converged Journal runtime.
-- Password material is provisioned separately through protected secret routes and
-- is intentionally absent from migration history.

BEGIN;

DO $$
DECLARE
  identity_name text;
  r record;
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'Dedicated Intelligence service identity migration must execute as postgres';
  END IF;

  FOREACH identity_name IN ARRAY ARRAY[
    'intelligence_app',
    'intelligence_recovery_app'
  ]
  LOOP
    SELECT * INTO r FROM pg_roles WHERE rolname = identity_name;
    IF NOT FOUND THEN
      EXECUTE format(
        'CREATE ROLE %I LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS',
        identity_name
      );
    ELSIF NOT r.rolcanlogin
       OR NOT r.rolinherit
       OR r.rolsuper
       OR r.rolcreatedb
       OR r.rolcreaterole
       OR r.rolreplication
       OR r.rolbypassrls THEN
      RAISE EXCEPTION 'Existing dedicated Intelligence identity % violates the least-privilege contract', identity_name;
    END IF;
  END LOOP;

  -- Keep the provider SET edge and the migration-controlled SET edge explicit for
  -- every role created in the shared Supabase project. Local PostgreSQL has no
  -- supabase_admin provider edge, so the same exact migration edge is sufficient.
  FOREACH identity_name IN ARRAY ARRAY[
    'intelligence_app',
    'intelligence_recovery_app'
  ]
  LOOP
    EXECUTE format('GRANT %I TO postgres WITH SET TRUE', identity_name);
  END LOOP;

  REVOKE intelligence_runtime FROM intelligence_app;
  REVOKE intelligence_recovery_admin FROM intelligence_recovery_app;
  GRANT intelligence_runtime TO intelligence_app;
  GRANT intelligence_recovery_admin TO intelligence_recovery_app;

  IF EXISTS (
    SELECT 1
    FROM pg_auth_members m
    JOIN pg_roles granted_role ON granted_role.oid = m.roleid
    JOIN pg_roles member_role ON member_role.oid = m.member
    JOIN pg_roles grantor_role ON grantor_role.oid = m.grantor
    WHERE (
      granted_role.rolname = ANY (ARRAY[
        'intelligence_runtime',
        'intelligence_recovery_admin',
        'intelligence_app',
        'intelligence_recovery_app'
      ])
      OR member_role.rolname = ANY (ARRAY[
        'intelligence_runtime',
        'intelligence_recovery_admin',
        'intelligence_app',
        'intelligence_recovery_app'
      ])
    )
    AND NOT (
      (
        member_role.rolname = 'postgres'
        AND granted_role.rolname = ANY (ARRAY[
          'intelligence_runtime',
          'intelligence_migrator',
          'intelligence_recovery_admin',
          'intelligence_app',
          'intelligence_recovery_app'
        ])
        AND (
          (
            grantor_role.rolname = 'supabase_admin'
            AND m.admin_option
            AND NOT m.inherit_option
            AND NOT m.set_option
          )
          OR (
            grantor_role.rolname = 'postgres'
            OR grantor_role.rolsuper
          )
          AND NOT m.admin_option
          AND m.inherit_option
          AND m.set_option
        )
      )
      OR (
        member_role.rolname = 'intelligence_app'
        AND granted_role.rolname = 'intelligence_runtime'
        AND (
          grantor_role.rolname = 'postgres'
          OR grantor_role.rolsuper
        )
        AND NOT m.admin_option
        AND m.inherit_option
        AND m.set_option
      )
      OR (
        member_role.rolname = 'intelligence_recovery_app'
        AND granted_role.rolname = 'intelligence_recovery_admin'
        AND (
          grantor_role.rolname = 'postgres'
          OR grantor_role.rolsuper
        )
        AND NOT m.admin_option
        AND m.inherit_option
        AND m.set_option
      )
    )
  ) THEN
    RAISE EXCEPTION 'Unexpected role membership involving dedicated Intelligence identities';
  END IF;
END
$$;

-- Existing lifecycle triggers authorize capability membership, rather than a
-- single hard-coded login name. This preserves the NOLOGIN privilege roles while
-- allowing the dedicated identities to use exactly those privileges.
DO $$
DECLARE
  function_sql text;
  function_oid oid;
BEGIN
  SELECT p.oid, pg_get_functiondef(p.oid)
    INTO function_oid, function_sql
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'intelligence'
    AND p.proname = 'execution_attempt_guard'
    AND pg_get_function_identity_arguments(p.oid) = '';

  IF function_oid IS NULL THEN
    RAISE EXCEPTION 'Intelligence execution attempt guard is absent';
  END IF;

  IF position('pg_has_role(current_user, ''intelligence_runtime'', ''member'')' IN function_sql) = 0 THEN
    function_sql := replace(
      function_sql,
      'current_user = ''intelligence_runtime''',
      'pg_has_role(current_user, ''intelligence_runtime'', ''member'')'
    );
  END IF;
  function_sql := replace(
    function_sql,
    'current_user NOT IN (''intelligence_migrator'', ''intelligence_recovery_admin'')',
    'current_user <> ''intelligence_migrator'' AND NOT pg_has_role(current_user, ''intelligence_recovery_admin'', ''member'')'
  );
  IF position('pg_has_role(current_user, ''intelligence_runtime'', ''member'')' IN function_sql) = 0
     OR position('pg_has_role(current_user, ''intelligence_recovery_admin'', ''member'')' IN function_sql) = 0 THEN
    RAISE EXCEPTION 'Intelligence execution attempt guard capability contract was not corrected';
  END IF;
  EXECUTE function_sql;

  SELECT pg_get_functiondef(p.oid)
    INTO function_sql
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'intelligence'
    AND p.proname = 'execution_result_attempt_guard'
    AND pg_get_function_identity_arguments(p.oid) = '';
  IF function_sql IS NULL THEN
    RAISE EXCEPTION 'Intelligence execution result guard is absent';
  END IF;
  IF position('pg_has_role(current_user, ''intelligence_runtime'', ''member'')' IN function_sql) = 0 THEN
    function_sql := replace(
      function_sql,
      'current_user = ''intelligence_runtime''',
      'pg_has_role(current_user, ''intelligence_runtime'', ''member'')'
    );
    EXECUTE function_sql;
  END IF;

  SELECT pg_get_functiondef(p.oid)
    INTO function_sql
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'intelligence'
    AND p.proname = 'browser_result_capability_guard'
    AND pg_get_function_identity_arguments(p.oid) = '';
  IF function_sql IS NULL THEN
    RAISE EXCEPTION 'Intelligence browser result guard is absent';
  END IF;
  IF position('pg_has_role(current_user, ''intelligence_runtime'', ''member'')' IN function_sql) = 0 THEN
    function_sql := replace(
      function_sql,
      'current_user = ''intelligence_runtime''',
      'pg_has_role(current_user, ''intelligence_runtime'', ''member'')'
    );
    EXECUTE function_sql;
  END IF;
END
$$;

INSERT INTO intelligence.schema_migrations (version, contract_family, source_lineage)
VALUES (9, 'DRANEKA_INTELLIGENCE_SERVICE_IDENTITIES_001', 'SHARED_SUPABASE_RUNTIME_IDENTITY')
ON CONFLICT (version) DO NOTHING;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM intelligence.schema_migrations
    WHERE version = 9
      AND (
        contract_family <> 'DRANEKA_INTELLIGENCE_SERVICE_IDENTITIES_001'
        OR source_lineage <> 'SHARED_SUPABASE_RUNTIME_IDENTITY'
      )
  ) THEN
    RAISE EXCEPTION 'Draneka Intelligence target migration 9 marker conflicts with the service identity contract';
  END IF;
END
$$;

COMMIT;
