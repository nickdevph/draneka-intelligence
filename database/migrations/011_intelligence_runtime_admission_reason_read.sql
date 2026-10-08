-- DRANEKA_INTELLIGENCE_RUNTIME_ADMISSION_REASON_READ_001
-- The Journal runtime validates the admitted projection and nonproduction
-- qualification scope before it creates a dispatch-authorized execution.
-- Keep this capability column-scoped; do not grant table-wide SELECT.

BEGIN;

DO $$
BEGIN
  IF current_user <> 'intelligence_migrator'
     AND NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = current_user AND rolsuper) THEN
    RAISE EXCEPTION 'Intelligence admission read migration requires intelligence_migrator';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM intelligence.schema_migrations
    WHERE version = 10
      AND contract_family = 'DRANEKA_INTELLIGENCE_OWNER_ACCOUNT_ERASURE_001'
  ) THEN
    RAISE EXCEPTION 'Intelligence owner account erasure migration 10 is required';
  END IF;
  IF to_regclass('intelligence.provider_admissions') IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM information_schema.columns
       WHERE table_schema = 'intelligence'
         AND table_name = 'provider_admissions'
         AND column_name = 'admission_reason'
     ) THEN
    RAISE EXCEPTION 'Intelligence provider admission contract is incomplete';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_roles
    WHERE rolname = 'intelligence_runtime'
      AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole
      AND NOT rolreplication AND NOT rolbypassrls
  ) THEN
    RAISE EXCEPTION 'The least-privilege Intelligence runtime role is required';
  END IF;
  IF EXISTS (
    SELECT 1 FROM intelligence.schema_migrations
    WHERE version = 11
      AND contract_family <> 'DRANEKA_INTELLIGENCE_RUNTIME_ADMISSION_REASON_READ_001'
  ) THEN
    RAISE EXCEPTION 'Intelligence migration 11 marker conflicts with this contract';
  END IF;
END
$$;

GRANT SELECT (admission_reason)
  ON TABLE intelligence.provider_admissions
  TO intelligence_runtime;

INSERT INTO intelligence.schema_migrations (version, contract_family, source_lineage)
VALUES (11, 'DRANEKA_INTELLIGENCE_RUNTIME_ADMISSION_REASON_READ_001', 'JOURNAL_RUNTIME_PROVIDER_ADMISSION_VALIDATION')
ON CONFLICT (version) DO NOTHING;

DO $$
BEGIN
  IF NOT has_column_privilege('intelligence_runtime', 'intelligence.provider_admissions', 'admission_reason', 'SELECT')
     OR has_column_privilege('intelligence_runtime', 'intelligence.provider_admissions', 'admitted_by', 'SELECT')
     OR has_table_privilege('intelligence_runtime', 'intelligence.provider_admissions', 'SELECT') THEN
    RAISE EXCEPTION 'Intelligence runtime admission reads do not match the column-scoped contract';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM intelligence.schema_migrations
    WHERE version = 11
      AND contract_family = 'DRANEKA_INTELLIGENCE_RUNTIME_ADMISSION_REASON_READ_001'
  ) THEN
    RAISE EXCEPTION 'Intelligence migration 11 marker was not installed';
  END IF;
END
$$;

COMMIT;
