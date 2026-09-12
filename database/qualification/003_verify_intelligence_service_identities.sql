-- DRANEKA_INTELLIGENCE_SERVICE_IDENTITIES_001 verification
-- Read-only exact-contract verification for the dedicated application and recovery
-- identities used by the converged Journal runtime.

BEGIN;
SET TRANSACTION READ ONLY;

DO $$
DECLARE
  expected_tables text[] := ARRAY[
    'analysis_requests',
    'analysis_context_bindings',
    'deterministic_opportunities',
    'deterministic_qualifications',
    'execution_jobs',
    'execution_attempts',
    'execution_results',
    'intake_events',
    'intake_evidence_items',
    'intake_decision_receipts',
    'provider_admissions',
    'system_trigger_admissions'
  ];
  expected_role text;
  function_name text;
BEGIN
  FOREACH expected_role IN ARRAY ARRAY[
    'intelligence_runtime',
    'intelligence_migrator',
    'intelligence_recovery_admin',
    'intelligence_app',
    'intelligence_recovery_app'
  ]
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = expected_role) THEN
      RAISE EXCEPTION 'FAIL: required Intelligence role % is absent', expected_role;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM pg_roles
    WHERE rolname IN ('intelligence_app', 'intelligence_recovery_app')
      AND (
        NOT rolcanlogin
        OR NOT rolinherit
        OR rolsuper
        OR rolcreatedb
        OR rolcreaterole
        OR rolreplication
        OR rolbypassrls
      )
  ) THEN
    RAISE EXCEPTION 'FAIL: dedicated Intelligence identity attributes are not least privilege';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_auth_members m
    JOIN pg_roles granted_role ON granted_role.oid = m.roleid
    JOIN pg_roles member_role ON member_role.oid = m.member
    JOIN pg_roles grantor_role ON grantor_role.oid = m.grantor
    WHERE (
      granted_role.rolname = ANY (ARRAY[
        'intelligence_runtime',
        'intelligence_migrator',
        'intelligence_recovery_admin',
        'intelligence_app',
        'intelligence_recovery_app'
      ])
      OR member_role.rolname = ANY (ARRAY[
        'intelligence_runtime',
        'intelligence_migrator',
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
            (
              grantor_role.rolname = 'postgres'
              OR grantor_role.rolsuper
            )
            AND NOT m.admin_option
            AND m.inherit_option
            AND m.set_option
          )
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
    RAISE EXCEPTION 'FAIL: unexpected membership involving the Intelligence identity family';
  END IF;

  IF NOT pg_has_role('intelligence_app', 'intelligence_runtime', 'member')
     OR NOT pg_has_role('intelligence_recovery_app', 'intelligence_recovery_admin', 'member') THEN
    RAISE EXCEPTION 'FAIL: dedicated identities do not inherit their exact capability roles';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_namespace n
    CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl, acldefault('n', n.nspowner))) acl
    JOIN pg_roles grantee_role ON grantee_role.oid = acl.grantee
    WHERE n.nspname = 'intelligence'
      AND grantee_role.rolname IN ('intelligence_app', 'intelligence_recovery_app')
  ) THEN
    RAISE EXCEPTION 'FAIL: dedicated identity has a direct Intelligence schema grant';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl
    JOIN pg_roles grantee_role ON grantee_role.oid = acl.grantee
    WHERE n.nspname = 'intelligence'
      AND c.relname = ANY(expected_tables)
      AND grantee_role.rolname IN ('intelligence_app', 'intelligence_recovery_app')
  ) THEN
    RAISE EXCEPTION 'FAIL: dedicated identity has a direct Intelligence table grant';
  END IF;

  IF NOT has_schema_privilege('intelligence_app', 'intelligence', 'USAGE')
     OR has_schema_privilege('intelligence_app', 'intelligence', 'CREATE')
     OR NOT has_schema_privilege('intelligence_recovery_app', 'intelligence', 'USAGE')
     OR has_schema_privilege('intelligence_recovery_app', 'intelligence', 'CREATE') THEN
    RAISE EXCEPTION 'FAIL: dedicated identity schema capability is incorrect';
  END IF;

  IF NOT has_table_privilege('intelligence_app', 'intelligence.analysis_requests', 'SELECT,INSERT,UPDATE')
     OR NOT has_table_privilege('intelligence_app', 'intelligence.execution_attempts', 'SELECT,INSERT,UPDATE')
     OR NOT has_table_privilege('intelligence_app', 'intelligence.execution_results', 'SELECT,INSERT')
     OR NOT has_table_privilege('intelligence_recovery_app', 'intelligence.execution_attempts', 'SELECT,INSERT,UPDATE')
     OR NOT has_table_privilege('intelligence_recovery_app', 'intelligence.execution_results', 'SELECT,INSERT') THEN
    RAISE EXCEPTION 'FAIL: inherited Intelligence table capability is incomplete';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_roles r
    WHERE r.rolname IN ('journal_app', 'journal_runtime', 'journal_migrator', 'journal_recovery_admin')
      AND (
        has_schema_privilege(r.rolname, 'intelligence', 'USAGE')
        OR EXISTS (
          SELECT 1
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = 'intelligence'
            AND c.relname = ANY(expected_tables)
            AND has_table_privilege(r.rolname, c.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
        )
      )
  ) THEN
    RAISE EXCEPTION 'FAIL: Journal role has direct Intelligence access';
  END IF;

  FOREACH function_name IN ARRAY ARRAY[
    'execution_attempt_guard',
    'execution_result_attempt_guard',
    'browser_result_capability_guard'
  ]
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'intelligence'
        AND p.proname = function_name
        AND position('pg_has_role(current_user, ''intelligence_runtime'', ''member'')' IN pg_get_functiondef(p.oid)) > 0
    ) THEN
      RAISE EXCEPTION 'FAIL: % does not use capability membership authorization', function_name;
    END IF;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'intelligence'
      AND p.proname = 'execution_attempt_guard'
      AND position('pg_has_role(current_user, ''intelligence_recovery_admin'', ''member'')' IN pg_get_functiondef(p.oid)) > 0
  ) THEN
    RAISE EXCEPTION 'FAIL: recovery expiry authorization does not use capability membership';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM intelligence.schema_migrations
    WHERE version = 9
      AND contract_family = 'DRANEKA_INTELLIGENCE_SERVICE_IDENTITIES_001'
      AND source_lineage = 'SHARED_SUPABASE_RUNTIME_IDENTITY'
  )
  OR (SELECT count(*) FROM intelligence.schema_migrations) <> 9 THEN
    RAISE EXCEPTION 'FAIL: dedicated service identity migration marker is absent or unexpected';
  END IF;
END
$$;

SELECT 'intelligence_service_identity_exact_contract' AS assertion, 'PASS' AS result;

ROLLBACK;
