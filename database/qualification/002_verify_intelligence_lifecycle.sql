-- DRANEKA_INTELLIGENCE_SUPABASE_LIFECYCLE_001 verification
-- Read-only exact-contract verification for the native target lifecycle schema.

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
  actual_count integer;
  expected_version integer;
  expected_family text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'intelligence') THEN
    RAISE EXCEPTION 'FAIL: intelligence schema is absent';
  END IF;

  SELECT count(*)::integer
  INTO actual_count
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'intelligence'
    AND c.relkind IN ('r', 'p')
    AND c.relname <> 'schema_migrations';
  IF actual_count <> cardinality(expected_tables) THEN
    RAISE EXCEPTION 'FAIL: target lifecycle table count expected %, found %', cardinality(expected_tables), actual_count;
  END IF;

  FOREACH expected_version IN ARRAY ARRAY[1, 2, 3, 4, 5, 6, 7, 8]
  LOOP
    IF NOT EXISTS (SELECT 1 FROM intelligence.schema_migrations WHERE version = expected_version) THEN
      RAISE EXCEPTION 'FAIL: missing native target migration version %', expected_version;
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM intelligence.schema_migrations) <> 8 THEN
    RAISE EXCEPTION 'FAIL: native target migration ledger contains unexpected versions';
  END IF;
  IF EXISTS (
    SELECT 1 FROM intelligence.schema_migrations
    WHERE version > 1 AND source_lineage IS DISTINCT FROM 'TRANSITIONAL_NEON_17_23'
  ) THEN
    RAISE EXCEPTION 'FAIL: lifecycle migration source lineage is not recorded exactly';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'intelligence'
      AND c.relkind IN ('r', 'p')
      AND c.relname <> 'schema_migrations'
      AND c.relname <> ALL(expected_tables)
  ) THEN
    RAISE EXCEPTION 'FAIL: unexpected relation in intelligence lifecycle schema';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_roles owner_role ON owner_role.oid = c.relowner
    WHERE n.nspname = 'intelligence'
      AND c.relname = ANY(expected_tables)
      AND owner_role.rolname <> 'intelligence_migrator'
  ) THEN
    RAISE EXCEPTION 'FAIL: lifecycle table owner mismatch';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'intelligence'
      AND c.relname = ANY(expected_tables)
      AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity)
  ) THEN
    RAISE EXCEPTION 'FAIL: lifecycle table RLS/FORCE RLS mismatch';
  END IF;

  FOREACH expected_family IN ARRAY expected_tables
  LOOP
    IF (SELECT count(*) FROM pg_policies WHERE schemaname = 'intelligence' AND tablename = expected_family) <> 3 THEN
      RAISE EXCEPTION 'FAIL: policy count mismatch for intelligence.%', expected_family;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl
    LEFT JOIN pg_roles grantee_role ON grantee_role.oid = acl.grantee
    WHERE n.nspname = 'intelligence'
      AND c.relname = ANY(expected_tables)
      AND coalesce(grantee_role.rolname, 'PUBLIC') NOT IN (
        'intelligence_migrator', 'intelligence_runtime', 'intelligence_recovery_admin'
      )
  ) THEN
    RAISE EXCEPTION 'FAIL: lifecycle table has an unauthorized ACL holder';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_roles r
    WHERE r.rolname IN ('anon', 'authenticated', 'journal_runtime', 'journal_migrator', 'journal_recovery_admin')
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
    RAISE EXCEPTION 'FAIL: peer or end-user role has direct Intelligence lifecycle access';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_constraint con
    JOIN pg_class child ON child.oid = con.conrelid
    JOIN pg_namespace child_ns ON child_ns.oid = child.relnamespace
    JOIN pg_class parent ON parent.oid = con.confrelid
    JOIN pg_namespace parent_ns ON parent_ns.oid = parent.relnamespace
    WHERE child_ns.nspname = 'intelligence'
      AND child.relname = ANY(expected_tables)
      AND parent_ns.nspname = 'public'
      AND parent.relname <> 'journal_tanks'
  ) THEN
    RAISE EXCEPTION 'FAIL: lifecycle schema references an unexpected public-domain table';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_constraint con
    JOIN pg_class child ON child.oid = con.conrelid
    JOIN pg_namespace child_ns ON child_ns.oid = child.relnamespace
    JOIN pg_class parent ON parent.oid = con.confrelid
    JOIN pg_namespace parent_ns ON parent_ns.oid = parent.relnamespace
    WHERE child_ns.nspname = 'intelligence'
      AND child.relname = ANY(expected_tables)
      AND parent_ns.nspname = 'public'
      AND parent.relname = 'journal_tanks'
      AND con.confdeltype <> 'r'
  ) THEN
    RAISE EXCEPTION 'FAIL: Journal Tank reference does not use ON DELETE RESTRICT';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'intelligence' AND p.proname = 'reject_append_only_mutation'
  ) THEN
    RAISE EXCEPTION 'FAIL: append-only guard function is absent';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'intelligence'
      AND c.relname = ANY(expected_tables)
      AND NOT t.tgisinternal
      AND t.tgname NOT IN (
        'intelligence_intake_events_immutable',
        'intelligence_intake_evidence_items_immutable',
        'intelligence_intake_decision_receipts_immutable',
        'intelligence_context_binding_guard',
        'intelligence_execution_job_guard',
        'intelligence_execution_result_guard',
        'intelligence_deterministic_opportunity_guard',
        'intelligence_deterministic_qualification_guard',
        'intelligence_provider_admission_guard',
        'intelligence_execution_attempt_guard',
        'intelligence_execution_result_attempt_guard',
        'intelligence_system_trigger_admission_guard',
        'intelligence_browser_result_capability_guard'
      )
  ) THEN
    RAISE EXCEPTION 'FAIL: unexpected lifecycle trigger';
  END IF;
END
$$;

SELECT 'intelligence_lifecycle_exact_contract' AS assertion, 'PASS' AS result;

ROLLBACK;
