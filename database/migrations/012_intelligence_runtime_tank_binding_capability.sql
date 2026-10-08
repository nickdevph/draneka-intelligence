-- DRANEKA_INTELLIGENCE_REQUEST_BOUND_TANK_IDENTITY_001
-- Allow the runtime to validate only a Tank/account pair already bound to a
-- durable Intelligence request. Do not grant it row reads on Journal Tanks.
BEGIN;

DO $$
BEGIN
  IF current_user <> 'intelligence_migrator'
     AND NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = current_user AND rolsuper) THEN
    RAISE EXCEPTION 'Request-bound Tank identity capability migration requires intelligence_migrator';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM intelligence.schema_migrations
    WHERE version = 11
      AND contract_family = 'DRANEKA_INTELLIGENCE_RUNTIME_ADMISSION_REASON_READ_001'
  ) THEN
    RAISE EXCEPTION 'Required Intelligence migration 11 is missing';
  END IF;
  IF to_regclass('intelligence.analysis_requests') IS NULL
     OR to_regnamespace('intelligence_internal') IS NULL
     OR to_regnamespace('journal_internal') IS NULL
     OR to_regprocedure('journal_internal.intelligence_runtime_tank_owner_matches(uuid,uuid)') IS NULL
     OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'intelligence_runtime')
     OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'intelligence_migrator') THEN
    RAISE EXCEPTION 'Request-bound Tank identity migration prerequisites are incomplete';
  END IF;
  IF NOT has_schema_privilege('intelligence_migrator', 'journal_internal', 'USAGE')
     OR NOT has_function_privilege(
       'intelligence_migrator',
       'journal_internal.intelligence_runtime_tank_owner_matches(uuid,uuid)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'Journal-owned Tank verification capability is not bound to the Intelligence migrator';
  END IF;
  IF has_any_column_privilege('intelligence_runtime', 'public.journal_tanks', 'SELECT')
     OR has_table_privilege('intelligence_runtime', 'public.journal_tanks', 'SELECT')
     OR EXISTS (
       SELECT 1 FROM pg_policies
       WHERE schemaname = 'public'
         AND tablename = 'journal_tanks'
         AND policyname = 'journal_tanks_intelligence_identity_select'
     ) THEN
    RAISE EXCEPTION 'Intelligence runtime must not retain direct Tank identity reads';
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION intelligence_internal.runtime_journal_tank_binding_is_current(
  p_analysis_request_id uuid,
  p_tank_id uuid,
  p_owner_user_id uuid
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
  SELECT p_analysis_request_id IS NOT NULL
     AND p_tank_id IS NOT NULL
     AND p_owner_user_id IS NOT NULL
     AND EXISTS (
       SELECT 1
       FROM intelligence.analysis_requests AS r
       WHERE r.id = p_analysis_request_id
         AND r.tank_id = p_tank_id
         AND r.owner_user_id = p_owner_user_id
         AND journal_internal.intelligence_runtime_tank_owner_matches(r.tank_id, r.owner_user_id)
     )
$$;

ALTER FUNCTION intelligence_internal.runtime_journal_tank_binding_is_current(uuid, uuid, uuid)
  OWNER TO intelligence_migrator;
REVOKE ALL ON SCHEMA intelligence_internal FROM PUBLIC, anon, authenticated, service_role,
  intelligence_runtime, intelligence_app, intelligence_recovery_admin, intelligence_recovery_app;
GRANT USAGE ON SCHEMA intelligence_internal TO intelligence_runtime, intelligence_migrator;
REVOKE ALL ON FUNCTION intelligence_internal.runtime_journal_tank_binding_is_current(uuid, uuid, uuid)
  FROM PUBLIC, anon, authenticated, service_role, intelligence_app,
       intelligence_recovery_admin, intelligence_recovery_app;
GRANT EXECUTE ON FUNCTION intelligence_internal.runtime_journal_tank_binding_is_current(uuid, uuid, uuid)
  TO intelligence_runtime;

INSERT INTO intelligence.schema_migrations (version, contract_family, source_lineage)
VALUES (12, 'DRANEKA_INTELLIGENCE_REQUEST_BOUND_TANK_IDENTITY_001', 'JOURNAL_040_TANK_IDENTITY_CAPABILITY')
ON CONFLICT (version) DO NOTHING;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM intelligence.schema_migrations
    WHERE version = 12
      AND contract_family = 'DRANEKA_INTELLIGENCE_REQUEST_BOUND_TANK_IDENTITY_001'
      AND source_lineage = 'JOURNAL_040_TANK_IDENTITY_CAPABILITY'
  ) THEN
    RAISE EXCEPTION 'Intelligence migration 12 marker conflicts with request-bound Tank identity contract';
  END IF;
  IF has_any_column_privilege('intelligence_runtime', 'public.journal_tanks', 'SELECT')
     OR NOT has_function_privilege(
       'intelligence_runtime',
       'intelligence_internal.runtime_journal_tank_binding_is_current(uuid,uuid,uuid)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'intelligence_runtime',
       'journal_internal.intelligence_runtime_tank_owner_matches(uuid,uuid)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'Request-bound Tank identity capability privileges do not match the contract';
  END IF;
END
$$;

COMMIT;
