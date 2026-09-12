-- DRANEKA_INTELLIGENCE_SUPABASE_LIFECYCLE_001
-- Compatibility-first target lifecycle schema.
-- Source lineage: transitional Neon Journal Intelligence migrations 17-23.
-- This migration creates only Intelligence-owned tables in the intelligence schema.
-- Journal source tables remain in public and are referenced read-only by identity.
-- Production execution is admitted only by the registered convergence Task Run.

BEGIN;

DO $$
BEGIN
  IF to_regclass('public.journal_tanks') IS NULL THEN
    RAISE EXCEPTION 'Journal-owned public.journal_tanks is required before Intelligence lifecycle bootstrap';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'intelligence_migrator')
     OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'intelligence_runtime')
     OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'intelligence_recovery_admin') THEN
    RAISE EXCEPTION 'Intelligence capability roles are required before lifecycle bootstrap';
  END IF;
  IF EXISTS (
    SELECT 1 FROM intelligence.schema_migrations
    WHERE version = 2
      AND contract_family <> 'DRANEKA_INTELLIGENCE_JI_INTAKE_ANALYSIS_001'
  ) THEN
    RAISE EXCEPTION 'Target migration 2 marker conflicts with the admitted contract family';
  END IF;
END
$$;


CREATE TABLE IF NOT EXISTS intelligence.analysis_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id uuid NOT NULL,
  tank_id uuid NOT NULL REFERENCES public.journal_tanks(id) ON DELETE RESTRICT,
  scope_token text NOT NULL,
  analysis_type text NOT NULL DEFAULT 'TANK_ANALYSIS',
  lane_class text NOT NULL DEFAULT 'ANALYTICAL',
  operation text NOT NULL,
  creation_source text NOT NULL DEFAULT 'WEB',
  question text NOT NULL,
  originating_context jsonb NOT NULL DEFAULT '{}'::jsonb,
  state text NOT NULL DEFAULT 'REQUESTED',
  revision integer NOT NULL DEFAULT 1,
  request_hash text NOT NULL,
  idempotency_key text NOT NULL,
  missing_information jsonb NOT NULL DEFAULT '[]'::jsonb,
  result jsonb,
  failure jsonb,
  freshness_state text NOT NULL DEFAULT 'UNKNOWN',
  conflict_state text NOT NULL DEFAULT 'NONE',
  ready_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT journal_analysis_requests_type_check CHECK (analysis_type = 'TANK_ANALYSIS'),
  CONSTRAINT journal_analysis_requests_lane_check CHECK (lane_class = 'ANALYTICAL'),
  CONSTRAINT journal_analysis_requests_operation_check CHECK (operation IN ('ON_DEMAND_ANALYSIS', 'COMPLIMENTARY_ANALYSIS')),
  CONSTRAINT journal_analysis_requests_source_check CHECK (creation_source IN ('WEB', 'ANDROID', 'JOURNAL_ROUTE', 'COMPLIMENTARY_GRANT', 'SCHEDULED_DAILY', 'REVIEWED_SUPPORT_HANDOFF')),
  CONSTRAINT journal_analysis_requests_state_check CHECK (state IN ('REQUESTED', 'PROCESSING', 'MORE_INFORMATION_NEEDED', 'READY', 'COMPLETED', 'FAILED_RETRYABLE', 'FAILED_TERMINAL', 'CANCELLED')),
  CONSTRAINT journal_analysis_requests_revision_check CHECK (revision > 0),
  CONSTRAINT journal_analysis_requests_question_check CHECK (char_length(question) BETWEEN 1 AND 2048),
  CONSTRAINT journal_analysis_requests_scope_token_check CHECK (char_length(scope_token) BETWEEN 1 AND 256),
  CONSTRAINT journal_analysis_requests_idempotency_check CHECK (char_length(idempotency_key) BETWEEN 1 AND 128),
  CONSTRAINT journal_analysis_requests_hash_check CHECK (char_length(request_hash) = 64),
  CONSTRAINT journal_analysis_requests_context_check CHECK (jsonb_typeof(originating_context) = 'object'),
  CONSTRAINT journal_analysis_requests_missing_check CHECK (jsonb_typeof(missing_information) = 'array'),
  CONSTRAINT journal_analysis_requests_result_check CHECK (result IS NULL OR jsonb_typeof(result) = 'object'),
  CONSTRAINT journal_analysis_requests_failure_check CHECK (failure IS NULL OR jsonb_typeof(failure) = 'object'),
  CONSTRAINT journal_analysis_requests_freshness_check CHECK (freshness_state IN ('FRESH', 'STALE', 'UNKNOWN')),
  CONSTRAINT journal_analysis_requests_conflict_check CHECK (conflict_state IN ('NONE', 'UNRESOLVED', 'UNKNOWN')),
  UNIQUE (owner_user_id, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_journal_analysis_requests_owner_updated
  ON intelligence.analysis_requests(owner_user_id, updated_at DESC, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_journal_analysis_requests_tank_state
  ON intelligence.analysis_requests(tank_id, state, updated_at DESC, id DESC);

ALTER TABLE intelligence.analysis_requests OWNER TO intelligence_migrator;
REVOKE ALL PRIVILEGES ON TABLE intelligence.analysis_requests FROM PUBLIC;
GRANT ALL PRIVILEGES ON TABLE intelligence.analysis_requests TO intelligence_migrator;
GRANT SELECT, INSERT, UPDATE ON TABLE intelligence.analysis_requests TO intelligence_runtime;
GRANT SELECT, INSERT, UPDATE ON TABLE intelligence.analysis_requests TO intelligence_recovery_admin;
ALTER TABLE intelligence.analysis_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE intelligence.analysis_requests FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS intelligence_analysis_requests_migrator ON intelligence.analysis_requests;
CREATE POLICY intelligence_analysis_requests_migrator
  ON intelligence.analysis_requests FOR ALL TO intelligence_migrator
  USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS intelligence_analysis_requests_runtime ON intelligence.analysis_requests;
CREATE POLICY intelligence_analysis_requests_runtime
  ON intelligence.analysis_requests FOR ALL TO intelligence_runtime
  USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS intelligence_analysis_requests_recovery ON intelligence.analysis_requests;
CREATE POLICY intelligence_analysis_requests_recovery
  ON intelligence.analysis_requests FOR ALL TO intelligence_recovery_admin
  USING (true) WITH CHECK (true);


CREATE TABLE IF NOT EXISTS intelligence.intake_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  source_type text NOT NULL,
  source_identity text NOT NULL,
  source_revision text NOT NULL,
  event_type text NOT NULL,
  evidence_authority jsonb NOT NULL DEFAULT '{}'::jsonb,
  source_handling_policy_version text NOT NULL,
  context_impact jsonb NOT NULL DEFAULT '{}'::jsonb,
  dependency_invalidations jsonb NOT NULL DEFAULT '[]'::jsonb,
  causation_id text,
  correlation_id text NOT NULL,
  replay_key text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT intelligence_intake_events_payload_object CHECK (jsonb_typeof(payload) = 'object'),
  CONSTRAINT intelligence_intake_events_authority_object CHECK (jsonb_typeof(evidence_authority) = 'object'),
  CONSTRAINT intelligence_intake_events_impact_object CHECK (jsonb_typeof(context_impact) = 'object'),
  CONSTRAINT intelligence_intake_events_invalidations_array CHECK (jsonb_typeof(dependency_invalidations) = 'array'),
  UNIQUE (source_type, source_identity, source_revision, event_type),
  UNIQUE (replay_key)
);

CREATE TABLE IF NOT EXISTS intelligence.intake_evidence_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  intake_event_id uuid NOT NULL REFERENCES intelligence.intake_events(id) ON DELETE RESTRICT,
  evidence_identity text NOT NULL,
  authority_dimension text NOT NULL,
  provenance jsonb NOT NULL DEFAULT '{}'::jsonb,
  content_fingerprint text NOT NULL,
  recorded_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (intake_event_id, evidence_identity)
);

CREATE TABLE IF NOT EXISTS intelligence.intake_decision_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  intake_event_id uuid NOT NULL REFERENCES intelligence.intake_events(id) ON DELETE RESTRICT,
  decision_version text NOT NULL,
  outcome text NOT NULL,
  admitted_operation text,
  reason_code text NOT NULL,
  immutable_receipt jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (intake_event_id),
  CONSTRAINT intelligence_intake_decision_receipts_outcome_check CHECK (outcome IN ('ADMITTED', 'REJECTED', 'NO_EXECUTION')),
  CONSTRAINT intelligence_intake_decision_receipts_payload_object CHECK (jsonb_typeof(immutable_receipt) = 'object')
);

CREATE INDEX IF NOT EXISTS idx_intelligence_intake_account_created
  ON intelligence.intake_events(account_id, created_at DESC, id DESC);

CREATE OR REPLACE FUNCTION intelligence.reject_append_only_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'Journal Intelligence records are append-only';
END
$$;

ALTER FUNCTION intelligence.reject_append_only_mutation() OWNER TO intelligence_migrator;
REVOKE ALL ON FUNCTION intelligence.reject_append_only_mutation() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION intelligence.reject_append_only_mutation() TO intelligence_migrator, intelligence_runtime, intelligence_recovery_admin;


DO $$
DECLARE
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'intake_events',
    'intake_evidence_items',
    'intake_decision_receipts'
  ]
  LOOP
    EXECUTE format('ALTER TABLE intelligence.%I OWNER TO intelligence_migrator', table_name);
    EXECUTE format('REVOKE ALL PRIVILEGES ON TABLE intelligence.%I FROM PUBLIC', table_name);
    EXECUTE format('GRANT ALL PRIVILEGES ON TABLE intelligence.%I TO intelligence_migrator', table_name);
    EXECUTE format('GRANT SELECT, INSERT ON TABLE intelligence.%I TO intelligence_runtime, intelligence_recovery_admin', table_name);
    EXECUTE format('ALTER TABLE intelligence.%I ENABLE ROW LEVEL SECURITY', table_name);
    EXECUTE format('ALTER TABLE intelligence.%I FORCE ROW LEVEL SECURITY', table_name);
    EXECUTE format('DROP POLICY IF EXISTS intelligence_' || table_name || '_migrator ON intelligence.' || table_name);
    EXECUTE format('CREATE POLICY intelligence_%s_migrator ON intelligence.%I FOR ALL TO intelligence_migrator USING (true) WITH CHECK (true)', table_name, table_name);
    EXECUTE format('DROP POLICY IF EXISTS intelligence_' || table_name || '_runtime ON intelligence.' || table_name);
    EXECUTE format('CREATE POLICY intelligence_%s_runtime ON intelligence.%I FOR ALL TO intelligence_runtime USING (true) WITH CHECK (true)', table_name, table_name);
    EXECUTE format('DROP POLICY IF EXISTS intelligence_' || table_name || '_recovery ON intelligence.' || table_name);
    EXECUTE format('CREATE POLICY intelligence_%s_recovery ON intelligence.%I FOR ALL TO intelligence_recovery_admin USING (true) WITH CHECK (true)', table_name, table_name);
  END LOOP;
END
$$;

DROP TRIGGER IF EXISTS intelligence_intake_events_immutable ON intelligence.intake_events;
CREATE TRIGGER intelligence_intake_events_immutable
  BEFORE UPDATE OR DELETE ON intelligence.intake_events
  FOR EACH ROW EXECUTE FUNCTION intelligence.reject_append_only_mutation();
DROP TRIGGER IF EXISTS intelligence_intake_evidence_items_immutable ON intelligence.intake_evidence_items;
CREATE TRIGGER intelligence_intake_evidence_items_immutable
  BEFORE UPDATE OR DELETE ON intelligence.intake_evidence_items
  FOR EACH ROW EXECUTE FUNCTION intelligence.reject_append_only_mutation();
DROP TRIGGER IF EXISTS intelligence_intake_decision_receipts_immutable ON intelligence.intake_decision_receipts;
CREATE TRIGGER intelligence_intake_decision_receipts_immutable
  BEFORE UPDATE OR DELETE ON intelligence.intake_decision_receipts
  FOR EACH ROW EXECUTE FUNCTION intelligence.reject_append_only_mutation();



INSERT INTO intelligence.schema_migrations (version, contract_family, source_lineage)
VALUES (2, 'DRANEKA_INTELLIGENCE_JI_INTAKE_ANALYSIS_001', 'TRANSITIONAL_NEON_17_23')
ON CONFLICT (version) DO NOTHING;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM intelligence.schema_migrations
    WHERE version = 2
      AND contract_family <> 'DRANEKA_INTELLIGENCE_JI_INTAKE_ANALYSIS_001'
  ) THEN
    RAISE EXCEPTION 'Draneka Intelligence target migration 2 marker conflicts with DRANEKA_INTELLIGENCE_JI_INTAKE_ANALYSIS_001';
  END IF;
END
$$;


-- Target migration 3: DRANEKA_INTELLIGENCE_JI_CONTEXT_EXECUTION_001
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM intelligence.schema_migrations
    WHERE version = 2
  ) THEN
    RAISE EXCEPTION 'Required preceding Intelligence migration 2 is not applied';
  END IF;
  IF EXISTS (
    SELECT 1 FROM intelligence.schema_migrations
    WHERE version = 3
      AND contract_family <> 'DRANEKA_INTELLIGENCE_JI_CONTEXT_EXECUTION_001'
  ) THEN
    RAISE EXCEPTION 'Target migration 3 marker conflicts with the admitted contract family';
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS intelligence.analysis_context_bindings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  analysis_request_id uuid NOT NULL REFERENCES intelligence.analysis_requests(id) ON DELETE RESTRICT,
  request_revision integer NOT NULL,
  processing_cycle integer NOT NULL,
  account_id uuid NOT NULL,
  tank_id uuid NOT NULL REFERENCES public.journal_tanks(id) ON DELETE RESTRICT,
  purpose text NOT NULL,
  bounded_context jsonb NOT NULL,
  context_fingerprint text NOT NULL,
  evidence_manifest jsonb NOT NULL DEFAULT '[]'::jsonb,
  material_dependency_manifest jsonb NOT NULL DEFAULT '[]'::jsonb,
  bound_at timestamptz NOT NULL DEFAULT now(),
  invalidated_at timestamptz,
  CONSTRAINT intelligence_context_object CHECK (jsonb_typeof(bounded_context) = 'object'),
  CONSTRAINT intelligence_context_evidence_array CHECK (jsonb_typeof(evidence_manifest) = 'array'),
  CONSTRAINT intelligence_context_dependencies_array CHECK (jsonb_typeof(material_dependency_manifest) = 'array'),
  UNIQUE (analysis_request_id, request_revision, processing_cycle)
);

CREATE TABLE IF NOT EXISTS intelligence.execution_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  analysis_request_id uuid NOT NULL REFERENCES intelligence.analysis_requests(id) ON DELETE RESTRICT,
  request_revision integer NOT NULL,
  processing_cycle integer NOT NULL,
  account_id uuid NOT NULL,
  tank_id uuid NOT NULL REFERENCES public.journal_tanks(id) ON DELETE RESTRICT,
  purpose text NOT NULL,
  context_binding_id uuid NOT NULL REFERENCES intelligence.analysis_context_bindings(id) ON DELETE RESTRICT,
  context_fingerprint text NOT NULL,
  material_dependency_manifest jsonb NOT NULL DEFAULT '[]'::jsonb,
  policy_reference text NOT NULL,
  provider_admission_reference text,
  status text NOT NULL DEFAULT 'PENDING',
  eligible_after timestamptz NOT NULL DEFAULT now(),
  dispatch_authorized_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT intelligence_execution_jobs_status_check CHECK (status IN ('PENDING', 'DISPATCH_AUTHORIZED', 'CLAIMED', 'PROCESSING', 'SUCCEEDED', 'FAILED_RETRYABLE', 'FAILED_TERMINAL', 'CANCELLED')),
  CONSTRAINT intelligence_job_dependencies_array CHECK (jsonb_typeof(material_dependency_manifest) = 'array'),
  UNIQUE (analysis_request_id, request_revision, processing_cycle)
);

CREATE TABLE IF NOT EXISTS intelligence.execution_results (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  execution_job_id uuid NOT NULL REFERENCES intelligence.execution_jobs(id) ON DELETE RESTRICT,
  attempt_id uuid,
  result_schema_version text NOT NULL,
  result_envelope jsonb NOT NULL,
  context_fingerprint text NOT NULL,
  integrity_identity text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT intelligence_result_object CHECK (jsonb_typeof(result_envelope) = 'object')
);

CREATE INDEX IF NOT EXISTS idx_intelligence_jobs_pending
  ON intelligence.execution_jobs(status, eligible_after, created_at, id);
CREATE INDEX IF NOT EXISTS idx_intelligence_jobs_account
  ON intelligence.execution_jobs(account_id, tank_id, created_at DESC);

CREATE OR REPLACE FUNCTION intelligence.context_binding_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'DELETE'
     OR NEW.analysis_request_id IS DISTINCT FROM OLD.analysis_request_id
     OR NEW.request_revision IS DISTINCT FROM OLD.request_revision
     OR NEW.processing_cycle IS DISTINCT FROM OLD.processing_cycle
     OR NEW.account_id IS DISTINCT FROM OLD.account_id
     OR NEW.tank_id IS DISTINCT FROM OLD.tank_id
     OR NEW.purpose IS DISTINCT FROM OLD.purpose
     OR NEW.bounded_context IS DISTINCT FROM OLD.bounded_context
     OR NEW.context_fingerprint IS DISTINCT FROM OLD.context_fingerprint
     OR NEW.evidence_manifest IS DISTINCT FROM OLD.evidence_manifest
     OR NEW.material_dependency_manifest IS DISTINCT FROM OLD.material_dependency_manifest
     OR NEW.bound_at IS DISTINCT FROM OLD.bound_at THEN
    RAISE EXCEPTION 'Journal Intelligence context binding identity is immutable';
  END IF;
  RETURN NEW;
END
$$;

CREATE OR REPLACE FUNCTION intelligence.execution_job_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'DELETE'
     OR NEW.analysis_request_id IS DISTINCT FROM OLD.analysis_request_id
     OR NEW.request_revision IS DISTINCT FROM OLD.request_revision
     OR NEW.processing_cycle IS DISTINCT FROM OLD.processing_cycle
     OR NEW.account_id IS DISTINCT FROM OLD.account_id
     OR NEW.tank_id IS DISTINCT FROM OLD.tank_id
     OR NEW.purpose IS DISTINCT FROM OLD.purpose
     OR NEW.context_binding_id IS DISTINCT FROM OLD.context_binding_id
     OR NEW.context_fingerprint IS DISTINCT FROM OLD.context_fingerprint
     OR NEW.material_dependency_manifest IS DISTINCT FROM OLD.material_dependency_manifest
     OR NEW.policy_reference IS DISTINCT FROM OLD.policy_reference
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'Journal Intelligence execution job identity is immutable';
  END IF;
  RETURN NEW;
END
$$;

CREATE OR REPLACE FUNCTION intelligence.execution_result_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'Journal Intelligence execution results are append-only';
END
$$;

ALTER FUNCTION intelligence.context_binding_guard() OWNER TO intelligence_migrator;
ALTER FUNCTION intelligence.execution_job_guard() OWNER TO intelligence_migrator;
ALTER FUNCTION intelligence.execution_result_guard() OWNER TO intelligence_migrator;
REVOKE ALL ON FUNCTION intelligence.context_binding_guard() FROM PUBLIC;
REVOKE ALL ON FUNCTION intelligence.execution_job_guard() FROM PUBLIC;
REVOKE ALL ON FUNCTION intelligence.execution_result_guard() FROM PUBLIC;

DO $$
DECLARE
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'analysis_context_bindings',
    'execution_jobs',
    'execution_results'
  ]
  LOOP
    EXECUTE format('ALTER TABLE intelligence.%I OWNER TO intelligence_migrator', table_name);
    EXECUTE format('REVOKE ALL PRIVILEGES ON TABLE intelligence.%I FROM PUBLIC, intelligence_runtime, intelligence_recovery_admin', table_name);
    EXECUTE format('GRANT ALL PRIVILEGES ON TABLE intelligence.%I TO intelligence_migrator', table_name);
    IF table_name = 'execution_results' THEN
      EXECUTE format('GRANT SELECT, INSERT ON TABLE intelligence.%I TO intelligence_runtime, intelligence_recovery_admin', table_name);
    ELSE
      EXECUTE format('GRANT SELECT, INSERT, UPDATE ON TABLE intelligence.%I TO intelligence_runtime, intelligence_recovery_admin', table_name);
    END IF;
    EXECUTE format('ALTER TABLE intelligence.%I ENABLE ROW LEVEL SECURITY', table_name);
    EXECUTE format('ALTER TABLE intelligence.%I FORCE ROW LEVEL SECURITY', table_name);
    EXECUTE format('DROP POLICY IF EXISTS %I ON intelligence.%I', table_name || '_migrator', table_name);
    EXECUTE format('CREATE POLICY %I ON intelligence.%I FOR ALL TO intelligence_migrator USING (true) WITH CHECK (true)', table_name || '_migrator', table_name);
    EXECUTE format('DROP POLICY IF EXISTS %I ON intelligence.%I', table_name || '_runtime', table_name);
    EXECUTE format('CREATE POLICY %I ON intelligence.%I FOR ALL TO intelligence_runtime USING (true) WITH CHECK (true)', table_name || '_runtime', table_name);
    EXECUTE format('DROP POLICY IF EXISTS %I ON intelligence.%I', table_name || '_recovery', table_name);
    EXECUTE format('CREATE POLICY %I ON intelligence.%I FOR ALL TO intelligence_recovery_admin USING (true) WITH CHECK (true)', table_name || '_recovery', table_name);
  END LOOP;
END
$$;

DROP TRIGGER IF EXISTS intelligence_context_binding_guard ON intelligence.analysis_context_bindings;
CREATE TRIGGER intelligence_context_binding_guard
  BEFORE UPDATE OR DELETE ON intelligence.analysis_context_bindings
  FOR EACH ROW EXECUTE FUNCTION intelligence.context_binding_guard();

DROP TRIGGER IF EXISTS intelligence_execution_job_guard ON intelligence.execution_jobs;
CREATE TRIGGER intelligence_execution_job_guard
  BEFORE UPDATE OR DELETE ON intelligence.execution_jobs
  FOR EACH ROW EXECUTE FUNCTION intelligence.execution_job_guard();

DROP TRIGGER IF EXISTS intelligence_execution_result_guard ON intelligence.execution_results;
CREATE TRIGGER intelligence_execution_result_guard
  BEFORE UPDATE OR DELETE ON intelligence.execution_results
  FOR EACH ROW EXECUTE FUNCTION intelligence.execution_result_guard();


INSERT INTO intelligence.schema_migrations (version, contract_family, source_lineage)
VALUES (3, 'DRANEKA_INTELLIGENCE_JI_CONTEXT_EXECUTION_001', 'TRANSITIONAL_NEON_17_23')
ON CONFLICT (version) DO NOTHING;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM intelligence.schema_migrations
    WHERE version = 3
      AND contract_family <> 'DRANEKA_INTELLIGENCE_JI_CONTEXT_EXECUTION_001'
  ) THEN
    RAISE EXCEPTION 'Draneka Intelligence target migration 3 marker conflicts with DRANEKA_INTELLIGENCE_JI_CONTEXT_EXECUTION_001';
  END IF;
END
$$;



-- Target migration 4: DRANEKA_INTELLIGENCE_JI_DETERMINISTIC_GOVERNANCE_001
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM intelligence.schema_migrations
    WHERE version = 3
  ) THEN
    RAISE EXCEPTION 'Required preceding Intelligence migration 3 is not applied';
  END IF;
  IF EXISTS (
    SELECT 1 FROM intelligence.schema_migrations
    WHERE version = 4
      AND contract_family <> 'DRANEKA_INTELLIGENCE_JI_DETERMINISTIC_GOVERNANCE_001'
  ) THEN
    RAISE EXCEPTION 'Target migration 4 marker conflicts with the admitted contract family';
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS intelligence.deterministic_opportunities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid,
  candidate_actor_ref text NOT NULL,
  created_by_actor_ref text NOT NULL,
  capability_key text NOT NULL,
  evidence_package jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'OBSERVED',
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT intelligence_opportunity_status_check CHECK (status IN ('OBSERVED', 'CANDIDATE', 'QUALIFIED', 'ADMITTED', 'REJECTED')),
  CONSTRAINT intelligence_opportunity_object CHECK (jsonb_typeof(evidence_package) = 'object')
);

CREATE TABLE IF NOT EXISTS intelligence.deterministic_qualifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  opportunity_id uuid NOT NULL REFERENCES intelligence.deterministic_opportunities(id) ON DELETE RESTRICT,
  candidate_identity text NOT NULL,
  candidate_actor_ref text NOT NULL,
  independent_reviewer_ref text NOT NULL,
  created_by_actor_ref text NOT NULL,
  verdict text NOT NULL,
  qualification_evidence jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT intelligence_qualification_verdict_check CHECK (verdict IN ('PASS', 'FAIL', 'BLOCKED')),
  CONSTRAINT intelligence_qualification_object CHECK (jsonb_typeof(qualification_evidence) = 'object'),
  CONSTRAINT intelligence_qualification_reviewer_distinct CHECK (independent_reviewer_ref <> candidate_identity AND independent_reviewer_ref <> candidate_actor_ref),
  CONSTRAINT intelligence_qualification_creator_check CHECK (created_by_actor_ref = independent_reviewer_ref)
);

CREATE OR REPLACE FUNCTION intelligence.deterministic_opportunity_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Deterministic opportunity identity is immutable';
  END IF;
  IF TG_OP = 'UPDATE'
     AND (NEW.id IS DISTINCT FROM OLD.id
       OR NEW.account_id IS DISTINCT FROM OLD.account_id
       OR NEW.candidate_actor_ref IS DISTINCT FROM OLD.candidate_actor_ref
       OR NEW.created_by_actor_ref IS DISTINCT FROM OLD.created_by_actor_ref
       OR NEW.capability_key IS DISTINCT FROM OLD.capability_key
       OR NEW.evidence_package IS DISTINCT FROM OLD.evidence_package
       OR NEW.created_at IS DISTINCT FROM OLD.created_at) THEN
    RAISE EXCEPTION 'Deterministic opportunity identity is immutable';
  END IF;
  IF NEW.status IN ('QUALIFIED', 'ADMITTED')
     AND current_user <> 'intelligence_migrator' THEN
    RAISE EXCEPTION 'Deterministic opportunity qualification/admission requires the governed migrator authority';
  END IF;
  IF NEW.status IN ('QUALIFIED', 'ADMITTED')
     AND NOT EXISTS (
       SELECT 1
       FROM intelligence.deterministic_qualifications q
       WHERE q.opportunity_id = NEW.id
         AND q.verdict = 'PASS'
         AND q.independent_reviewer_ref <> NEW.candidate_actor_ref
     ) THEN
    RAISE EXCEPTION 'Deterministic opportunity admission requires an independent PASS qualification';
  END IF;
  RETURN NEW;
END
$$;

CREATE OR REPLACE FUNCTION intelligence.deterministic_qualification_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT'
     AND NOT EXISTS (
       SELECT 1
       FROM intelligence.deterministic_opportunities o
       WHERE o.id = NEW.opportunity_id
         AND o.candidate_actor_ref = NEW.candidate_actor_ref
     ) THEN
    RAISE EXCEPTION 'Deterministic qualification candidate actor does not match its opportunity';
  END IF;
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'Deterministic qualification records are append-only';
  END IF;
  RETURN NEW;
END
$$;

ALTER FUNCTION intelligence.deterministic_opportunity_guard() OWNER TO intelligence_migrator;
ALTER FUNCTION intelligence.deterministic_qualification_guard() OWNER TO intelligence_migrator;
REVOKE ALL ON FUNCTION intelligence.deterministic_opportunity_guard() FROM PUBLIC;
REVOKE ALL ON FUNCTION intelligence.deterministic_qualification_guard() FROM PUBLIC;

DO $$
DECLARE
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'deterministic_opportunities',
    'deterministic_qualifications'
  ]
  LOOP
    EXECUTE format('ALTER TABLE intelligence.%I OWNER TO intelligence_migrator', table_name);
    EXECUTE format('REVOKE ALL PRIVILEGES ON TABLE intelligence.%I FROM PUBLIC, intelligence_runtime, intelligence_recovery_admin', table_name);
    EXECUTE format('GRANT ALL PRIVILEGES ON TABLE intelligence.%I TO intelligence_migrator', table_name);
    IF table_name = 'deterministic_opportunities' THEN
      EXECUTE format('GRANT SELECT, INSERT ON TABLE intelligence.%I TO intelligence_runtime, intelligence_recovery_admin', table_name);
    ELSE
      EXECUTE format('GRANT SELECT, INSERT ON TABLE intelligence.%I TO intelligence_runtime, intelligence_recovery_admin', table_name);
    END IF;
    EXECUTE format('ALTER TABLE intelligence.%I ENABLE ROW LEVEL SECURITY', table_name);
    EXECUTE format('ALTER TABLE intelligence.%I FORCE ROW LEVEL SECURITY', table_name);
    EXECUTE format('DROP POLICY IF EXISTS %I ON intelligence.%I', table_name || '_migrator', table_name);
    EXECUTE format('CREATE POLICY %I ON intelligence.%I FOR ALL TO intelligence_migrator USING (true) WITH CHECK (true)', table_name || '_migrator', table_name);
    EXECUTE format('DROP POLICY IF EXISTS %I ON intelligence.%I', table_name || '_runtime', table_name);
    EXECUTE format('CREATE POLICY %I ON intelligence.%I FOR ALL TO intelligence_runtime USING (true) WITH CHECK (true)', table_name || '_runtime', table_name);
    EXECUTE format('DROP POLICY IF EXISTS %I ON intelligence.%I', table_name || '_recovery', table_name);
    EXECUTE format('CREATE POLICY %I ON intelligence.%I FOR ALL TO intelligence_recovery_admin USING (true) WITH CHECK (true)', table_name || '_recovery', table_name);
  END LOOP;
END
$$;

DROP TRIGGER IF EXISTS intelligence_deterministic_opportunity_guard ON intelligence.deterministic_opportunities;
CREATE TRIGGER intelligence_deterministic_opportunity_guard
  BEFORE INSERT OR UPDATE OR DELETE ON intelligence.deterministic_opportunities
  FOR EACH ROW EXECUTE FUNCTION intelligence.deterministic_opportunity_guard();

DROP TRIGGER IF EXISTS intelligence_deterministic_qualification_guard ON intelligence.deterministic_qualifications;
CREATE TRIGGER intelligence_deterministic_qualification_guard
  BEFORE INSERT OR UPDATE OR DELETE ON intelligence.deterministic_qualifications
  FOR EACH ROW EXECUTE FUNCTION intelligence.deterministic_qualification_guard();


INSERT INTO intelligence.schema_migrations (version, contract_family, source_lineage)
VALUES (4, 'DRANEKA_INTELLIGENCE_JI_DETERMINISTIC_GOVERNANCE_001', 'TRANSITIONAL_NEON_17_23')
ON CONFLICT (version) DO NOTHING;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM intelligence.schema_migrations
    WHERE version = 4
      AND contract_family <> 'DRANEKA_INTELLIGENCE_JI_DETERMINISTIC_GOVERNANCE_001'
  ) THEN
    RAISE EXCEPTION 'Draneka Intelligence target migration 4 marker conflicts with DRANEKA_INTELLIGENCE_JI_DETERMINISTIC_GOVERNANCE_001';
  END IF;
END
$$;



-- Target migration 5: DRANEKA_INTELLIGENCE_JI_PROVIDER_GOVERNANCE_001
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM intelligence.schema_migrations
    WHERE version = 4
  ) THEN
    RAISE EXCEPTION 'Required preceding Intelligence migration 4 is not applied';
  END IF;
  IF EXISTS (
    SELECT 1 FROM intelligence.schema_migrations
    WHERE version = 5
      AND contract_family <> 'DRANEKA_INTELLIGENCE_JI_PROVIDER_GOVERNANCE_001'
  ) THEN
    RAISE EXCEPTION 'Target migration 5 marker conflicts with the admitted contract family';
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION intelligence.provider_projection_is_safe(projection jsonb)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF jsonb_typeof(projection) <> 'object'
     OR projection ?| ARRAY['secret', 'credential', 'credentials', 'password', 'token_value', 'private_data']
     OR (SELECT count(*) FROM jsonb_object_keys(projection)) <> 1
     OR NOT (projection ? 'fields')
     OR jsonb_typeof(projection->'fields') <> 'array' THEN
    RETURN false;
  END IF;
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(projection->'fields') AS field(value)
    WHERE jsonb_typeof(field.value) <> 'string'
       OR field.value #>> '{}' NOT IN (
         'analysis_request_id', 'request_revision', 'processing_cycle',
         'account_scope_token', 'tank_scope_token', 'purpose',
         'bounded_tank_context', 'evidence_manifest', 'provenance',
         'material_dependency_manifest', 'context_fingerprint',
         'deadline_at', 'correlation_id', 'result_schema_version'
       )
  ) THEN
    RETURN false;
  END IF;
  RETURN true;
EXCEPTION WHEN others THEN
  RETURN false;
END
$$;

ALTER FUNCTION intelligence.provider_projection_is_safe(jsonb) OWNER TO intelligence_migrator;
REVOKE ALL ON FUNCTION intelligence.provider_projection_is_safe(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION intelligence.provider_projection_is_safe(jsonb)
  TO intelligence_migrator, intelligence_runtime, intelligence_recovery_admin;

CREATE TABLE IF NOT EXISTS intelligence.provider_admissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  adapter_key text NOT NULL,
  adapter_version text NOT NULL,
  status text NOT NULL DEFAULT 'REVOKED',
  allowed_projection jsonb NOT NULL DEFAULT '{"fields":[]}'::jsonb,
  result_schema_version text NOT NULL,
  admission_reason text NOT NULL,
  admitted_by text,
  admitted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT intelligence_provider_admission_status_check CHECK (status IN ('DRAFT', 'ACTIVE', 'REVOKED')),
  CONSTRAINT intelligence_provider_admission_projection_safe CHECK (intelligence.provider_projection_is_safe(allowed_projection)),
  CONSTRAINT intelligence_provider_admission_adapter_key_nonempty CHECK (btrim(adapter_key) <> ''),
  CONSTRAINT intelligence_provider_admission_adapter_version_nonempty CHECK (btrim(adapter_version) <> ''),
  CONSTRAINT intelligence_provider_admission_active_metadata CHECK (
    (status = 'ACTIVE' AND admitted_by IS NOT NULL AND admitted_at IS NOT NULL AND revoked_at IS NULL)
    OR status <> 'ACTIVE'
  ),
  CONSTRAINT intelligence_provider_admission_revoked_metadata CHECK (
    (status = 'REVOKED' AND revoked_at IS NOT NULL)
    OR status <> 'REVOKED'
  ),
  UNIQUE (adapter_key, adapter_version)
);

CREATE INDEX IF NOT EXISTS idx_intelligence_provider_admissions_active
  ON intelligence.provider_admissions(adapter_key, adapter_version, status);

CREATE OR REPLACE FUNCTION intelligence.provider_admission_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Provider admission identity is immutable';
  END IF;
  IF TG_OP = 'INSERT' AND NEW.status = 'REVOKED' AND NEW.revoked_at IS NULL THEN
    NEW.revoked_at := coalesce(NEW.created_at, now());
  END IF;
  IF TG_OP = 'UPDATE'
     AND (NEW.id IS DISTINCT FROM OLD.id
       OR NEW.adapter_key IS DISTINCT FROM OLD.adapter_key
       OR NEW.adapter_version IS DISTINCT FROM OLD.adapter_version
       OR NEW.allowed_projection IS DISTINCT FROM OLD.allowed_projection
       OR NEW.result_schema_version IS DISTINCT FROM OLD.result_schema_version
       OR NEW.admission_reason IS DISTINCT FROM OLD.admission_reason
       OR NEW.created_at IS DISTINCT FROM OLD.created_at) THEN
    RAISE EXCEPTION 'Provider admission identity is immutable';
  END IF;
  IF current_user <> 'intelligence_migrator'
     AND NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = current_user AND rolsuper) THEN
    RAISE EXCEPTION 'Provider admission changes require the governed migrator authority';
  END IF;
  IF TG_OP = 'UPDATE'
     AND OLD.status = 'REVOKED'
     AND NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'Revoked provider admission is terminal; issue a new adapter version';
  END IF;
  IF TG_OP = 'UPDATE'
     AND OLD.status <> 'REVOKED'
     AND NEW.status = 'REVOKED'
     AND NEW.revoked_at IS NULL THEN
    RAISE EXCEPTION 'Provider revocation requires a revocation time';
  END IF;
  IF NEW.status = 'ACTIVE'
     AND (NEW.admitted_by IS NULL OR btrim(NEW.admitted_by) = '' OR NEW.admitted_at IS NULL) THEN
    RAISE EXCEPTION 'Active provider admission requires admission identity and time';
  END IF;
  IF NEW.status = 'ACTIVE'
     AND NEW.admitted_by IS DISTINCT FROM current_user THEN
    RAISE EXCEPTION 'Active provider admission identity must match the governed database actor';
  END IF;
  IF NEW.status = 'REVOKED'
     AND NEW.revoked_at IS NULL THEN
    RAISE EXCEPTION 'Revoked provider admission requires revocation time';
  END IF;
  RETURN NEW;
END
$$;

ALTER FUNCTION intelligence.provider_admission_guard() OWNER TO intelligence_migrator;
REVOKE ALL ON FUNCTION intelligence.provider_admission_guard() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION intelligence.provider_admission_guard() TO intelligence_migrator, intelligence_runtime, intelligence_recovery_admin;

ALTER TABLE intelligence.provider_admissions OWNER TO intelligence_migrator;
REVOKE ALL PRIVILEGES ON TABLE intelligence.provider_admissions FROM PUBLIC, intelligence_runtime, intelligence_recovery_admin;
GRANT ALL PRIVILEGES ON TABLE intelligence.provider_admissions TO intelligence_migrator;
GRANT SELECT (id, adapter_key, adapter_version, status, allowed_projection, result_schema_version, admitted_at, revoked_at)
  ON TABLE intelligence.provider_admissions TO intelligence_runtime;
GRANT SELECT ON TABLE intelligence.provider_admissions TO intelligence_recovery_admin;
ALTER TABLE intelligence.provider_admissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE intelligence.provider_admissions FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS intelligence_provider_admissions_migrator ON intelligence.provider_admissions;
CREATE POLICY intelligence_provider_admissions_migrator
  ON intelligence.provider_admissions FOR ALL TO intelligence_migrator
  USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS intelligence_provider_admissions_runtime ON intelligence.provider_admissions;
CREATE POLICY intelligence_provider_admissions_runtime
  ON intelligence.provider_admissions FOR SELECT TO intelligence_runtime
  USING (true);
DROP POLICY IF EXISTS intelligence_provider_admissions_recovery ON intelligence.provider_admissions;
CREATE POLICY intelligence_provider_admissions_recovery
  ON intelligence.provider_admissions FOR SELECT TO intelligence_recovery_admin
  USING (true);

DROP TRIGGER IF EXISTS intelligence_provider_admission_guard ON intelligence.provider_admissions;
CREATE TRIGGER intelligence_provider_admission_guard
  BEFORE INSERT OR UPDATE OR DELETE ON intelligence.provider_admissions
  FOR EACH ROW EXECUTE FUNCTION intelligence.provider_admission_guard();


INSERT INTO intelligence.schema_migrations (version, contract_family, source_lineage)
VALUES (5, 'DRANEKA_INTELLIGENCE_JI_PROVIDER_GOVERNANCE_001', 'TRANSITIONAL_NEON_17_23')
ON CONFLICT (version) DO NOTHING;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM intelligence.schema_migrations
    WHERE version = 5
      AND contract_family <> 'DRANEKA_INTELLIGENCE_JI_PROVIDER_GOVERNANCE_001'
  ) THEN
    RAISE EXCEPTION 'Draneka Intelligence target migration 5 marker conflicts with DRANEKA_INTELLIGENCE_JI_PROVIDER_GOVERNANCE_001';
  END IF;
END
$$;



-- Target migration 6: DRANEKA_INTELLIGENCE_JI_ATTEMPTS_001
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM intelligence.schema_migrations
    WHERE version = 5
  ) THEN
    RAISE EXCEPTION 'Required preceding Intelligence migration 5 is not applied';
  END IF;
  IF EXISTS (
    SELECT 1 FROM intelligence.schema_migrations
    WHERE version = 6
      AND contract_family <> 'DRANEKA_INTELLIGENCE_JI_ATTEMPTS_001'
  ) THEN
    RAISE EXCEPTION 'Target migration 6 marker conflicts with the admitted contract family';
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS intelligence.execution_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  execution_job_id uuid NOT NULL REFERENCES intelligence.execution_jobs(id) ON DELETE RESTRICT,
  attempt_sequence integer NOT NULL,
  adapter_key text NOT NULL,
  adapter_version text NOT NULL,
  provider_admission_id uuid NOT NULL REFERENCES intelligence.provider_admissions(id) ON DELETE RESTRICT,
  provider_idempotency_key text NOT NULL,
  deadline_at timestamptz NOT NULL,
  predecessor_attempt_id uuid REFERENCES intelligence.execution_attempts(id) ON DELETE RESTRICT,
  state text NOT NULL DEFAULT 'READY',
  claim_token_hash text,
  claimed_by text,
  claim_expires_at timestamptz,
  terminal_reason text,
  result_id uuid REFERENCES intelligence.execution_results(id) ON DELETE RESTRICT,
  acceptance_disposition text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT intelligence_attempt_sequence_positive CHECK (attempt_sequence > 0),
  CONSTRAINT intelligence_attempt_adapter_key_nonempty CHECK (btrim(adapter_key) <> ''),
  CONSTRAINT intelligence_attempt_adapter_version_nonempty CHECK (btrim(adapter_version) <> ''),
  CONSTRAINT intelligence_attempt_idempotency_key_nonempty CHECK (btrim(provider_idempotency_key) <> ''),
  CONSTRAINT intelligence_attempt_predecessor_not_self CHECK (predecessor_attempt_id IS NULL OR predecessor_attempt_id <> id),
  CONSTRAINT intelligence_attempt_claim_token_nonempty CHECK (claim_token_hash IS NULL OR btrim(claim_token_hash) <> ''),
  CONSTRAINT intelligence_attempt_claimant_nonempty CHECK (claimed_by IS NULL OR btrim(claimed_by) <> ''),
  CONSTRAINT intelligence_attempt_ready_has_no_claim CHECK (
    state <> 'READY' OR (claim_token_hash IS NULL AND claimed_by IS NULL AND claim_expires_at IS NULL)
  ),
  CONSTRAINT intelligence_attempt_active_claim_complete CHECK (
    state NOT IN ('CLAIMED', 'PROCESSING')
    OR (claim_token_hash IS NOT NULL AND claimed_by IS NOT NULL AND claim_expires_at IS NOT NULL)
  ),
  CONSTRAINT intelligence_attempt_state_check CHECK (state IN ('READY', 'CLAIMED', 'PROCESSING', 'SUCCEEDED', 'REJECTED', 'FAILED_RETRYABLE', 'FAILED_TERMINAL', 'EXPIRED')),
  CONSTRAINT intelligence_acceptance_disposition_check CHECK (acceptance_disposition IS NULL OR acceptance_disposition IN ('ELIGIBLE_ACCEPTED', 'REJECTED_STALE', 'REJECTED_MALFORMED', 'REJECTED_SCOPE', 'REJECTED_ADMISSION', 'REJECTED_CANCELLED', 'REJECTED_DUPLICATE')),
  CONSTRAINT intelligence_attempt_success_result_check CHECK (state <> 'SUCCEEDED' OR (result_id IS NOT NULL AND acceptance_disposition = 'ELIGIBLE_ACCEPTED')),
  CONSTRAINT intelligence_attempt_rejected_result_check CHECK (state <> 'REJECTED' OR (result_id IS NOT NULL AND acceptance_disposition LIKE 'REJECTED_%')),
  UNIQUE (execution_job_id, attempt_sequence),
  UNIQUE (provider_idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_intelligence_attempts_claimable
  ON intelligence.execution_attempts(state, claim_expires_at, created_at, id);

CREATE OR REPLACE FUNCTION intelligence.execution_attempt_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Journal Intelligence execution attempts are not deletable';
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.state <> 'READY' THEN
      RAISE EXCEPTION 'New execution attempts must enter in READY state';
    END IF;
    IF NEW.result_id IS NOT NULL OR NEW.acceptance_disposition IS NOT NULL THEN
      RAISE EXCEPTION 'New execution attempts cannot have a result or acceptance disposition';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM intelligence.provider_admissions p
      WHERE p.id = NEW.provider_admission_id
        AND p.adapter_key = NEW.adapter_key
        AND p.adapter_version = NEW.adapter_version
        AND p.status = 'ACTIVE'
    ) THEN
      RAISE EXCEPTION 'Execution attempt requires a current active provider admission';
    END IF;
    IF NEW.predecessor_attempt_id IS NOT NULL
       AND NOT EXISTS (
         SELECT 1
         FROM intelligence.execution_attempts predecessor
         WHERE predecessor.id = NEW.predecessor_attempt_id
           AND predecessor.execution_job_id = NEW.execution_job_id
           AND predecessor.attempt_sequence < NEW.attempt_sequence
           AND predecessor.state IN ('FAILED_RETRYABLE', 'EXPIRED')
       ) THEN
      RAISE EXCEPTION 'Execution attempt predecessor must belong to the same job and precede the new attempt';
    END IF;
    RETURN NEW;
  END IF;
  IF pg_has_role(current_user, 'intelligence_runtime', 'member')
     AND OLD.state = 'READY'
     AND NEW.state <> 'CLAIMED' THEN
    RAISE EXCEPTION 'Runtime can only claim a READY execution attempt';
  END IF;
  IF pg_has_role(current_user, 'intelligence_runtime', 'member')
     AND OLD.state = 'READY'
     AND NEW.state = 'CLAIMED'
     AND current_setting('app.intelligence_work_identity', true) IS DISTINCT FROM NEW.claimed_by THEN
    RAISE EXCEPTION 'Execution attempt claim requires the claiming worker identity';
  END IF;
  IF NEW.state = 'EXPIRED'
     AND current_user <> 'intelligence_migrator'
     AND NOT pg_has_role(current_user, 'intelligence_recovery_admin', 'member')
     AND NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = current_user AND rolsuper) THEN
    RAISE EXCEPTION 'Execution attempt expiry requires the recovery authority';
  END IF;
  IF pg_has_role(current_user, 'intelligence_runtime', 'member')
     AND OLD.state IN ('CLAIMED', 'PROCESSING')
     AND current_setting('app.intelligence_work_identity', true) IS DISTINCT FROM OLD.claimed_by THEN
    RAISE EXCEPTION 'Execution attempt update requires the current claim owner';
  END IF;
  IF OLD.state IN ('CLAIMED', 'PROCESSING')
     AND NEW.state IN ('PROCESSING', 'SUCCEEDED', 'REJECTED', 'FAILED_RETRYABLE', 'FAILED_TERMINAL')
     AND OLD.claim_expires_at <= now() THEN
    RAISE EXCEPTION 'Execution attempt claim lease has expired';
  END IF;
  IF NEW.state IN ('CLAIMED', 'PROCESSING')
     AND (NEW.claim_token_hash IS NULL OR NEW.claimed_by IS NULL OR NEW.claim_expires_at IS NULL OR NEW.claim_expires_at <= now()) THEN
    RAISE EXCEPTION 'Active execution claim requires an unexpired lease';
  END IF;
  IF NEW.result_id IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM intelligence.execution_results result
       WHERE result.id = NEW.result_id
         AND result.execution_job_id = NEW.execution_job_id
         AND result.attempt_id = NEW.id
     ) THEN
    RAISE EXCEPTION 'Execution attempt result must be bound to the same attempt and job';
  END IF;
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.execution_job_id IS DISTINCT FROM OLD.execution_job_id
     OR NEW.attempt_sequence IS DISTINCT FROM OLD.attempt_sequence
     OR NEW.adapter_key IS DISTINCT FROM OLD.adapter_key
     OR NEW.adapter_version IS DISTINCT FROM OLD.adapter_version
     OR NEW.provider_admission_id IS DISTINCT FROM OLD.provider_admission_id
     OR NEW.provider_idempotency_key IS DISTINCT FROM OLD.provider_idempotency_key
     OR NEW.deadline_at IS DISTINCT FROM OLD.deadline_at
     OR NEW.predecessor_attempt_id IS DISTINCT FROM OLD.predecessor_attempt_id
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'Journal Intelligence execution attempt identity is immutable';
  END IF;
  IF OLD.result_id IS NOT NULL AND NEW.result_id IS DISTINCT FROM OLD.result_id THEN
    RAISE EXCEPTION 'Journal Intelligence attempt result identity is immutable';
  END IF;
  IF OLD.acceptance_disposition IS NOT NULL
     AND NEW.acceptance_disposition IS DISTINCT FROM OLD.acceptance_disposition THEN
    RAISE EXCEPTION 'Journal Intelligence acceptance disposition is immutable';
  END IF;
  IF OLD.claim_token_hash IS NOT NULL
     AND NEW.claim_token_hash IS DISTINCT FROM OLD.claim_token_hash THEN
    RAISE EXCEPTION 'Journal Intelligence claim token identity is immutable';
  END IF;
  IF OLD.claimed_by IS NOT NULL
     AND NEW.claimed_by IS DISTINCT FROM OLD.claimed_by THEN
    RAISE EXCEPTION 'Journal Intelligence claimant identity is immutable';
  END IF;
  IF OLD.state IN ('SUCCEEDED', 'REJECTED', 'FAILED_TERMINAL', 'EXPIRED')
     AND (NEW.claim_token_hash IS DISTINCT FROM OLD.claim_token_hash
       OR NEW.claimed_by IS DISTINCT FROM OLD.claimed_by
       OR NEW.claim_expires_at IS DISTINCT FROM OLD.claim_expires_at) THEN
    RAISE EXCEPTION 'Terminal execution claim metadata is immutable';
  END IF;
  IF OLD.state IN ('SUCCEEDED', 'REJECTED', 'FAILED_TERMINAL', 'EXPIRED')
     AND NEW.state IS DISTINCT FROM OLD.state THEN
    RAISE EXCEPTION 'Terminal execution attempts cannot change state';
  END IF;
  IF OLD.state = 'READY' AND NEW.state NOT IN ('READY', 'CLAIMED', 'FAILED_TERMINAL', 'EXPIRED') THEN
    RAISE EXCEPTION 'Invalid execution attempt state transition from READY';
  END IF;
  IF OLD.state = 'CLAIMED' AND NEW.state NOT IN ('CLAIMED', 'PROCESSING', 'SUCCEEDED', 'REJECTED', 'FAILED_RETRYABLE', 'FAILED_TERMINAL', 'EXPIRED') THEN
    RAISE EXCEPTION 'Invalid execution attempt state transition from CLAIMED';
  END IF;
  IF OLD.state = 'PROCESSING' AND NEW.state NOT IN ('PROCESSING', 'SUCCEEDED', 'REJECTED', 'FAILED_RETRYABLE', 'FAILED_TERMINAL', 'EXPIRED') THEN
    RAISE EXCEPTION 'Invalid execution attempt state transition from PROCESSING';
  END IF;
  IF OLD.state = 'FAILED_RETRYABLE' AND NEW.state NOT IN ('FAILED_RETRYABLE', 'FAILED_TERMINAL', 'EXPIRED') THEN
    RAISE EXCEPTION 'Invalid execution attempt state transition from FAILED_RETRYABLE';
  END IF;
  RETURN NEW;
END
$$;

CREATE OR REPLACE FUNCTION intelligence.execution_result_attempt_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  attempt_row record;
BEGIN
  IF NEW.attempt_id IS NULL THEN
    RAISE EXCEPTION 'New execution results require an execution attempt';
  END IF;
  SELECT id, execution_job_id, claimed_by
  INTO attempt_row
  FROM intelligence.execution_attempts
  WHERE id = NEW.attempt_id;
  IF NOT FOUND OR attempt_row.execution_job_id IS DISTINCT FROM NEW.execution_job_id THEN
    RAISE EXCEPTION 'Execution result must reference an attempt from the same job';
  END IF;
  IF pg_has_role(current_user, 'intelligence_runtime', 'member')
     AND current_setting('app.intelligence_work_identity', true) IS DISTINCT FROM attempt_row.claimed_by THEN
    RAISE EXCEPTION 'Execution result insert requires the current claim owner';
  END IF;
  RETURN NEW;
END
$$;

ALTER FUNCTION intelligence.execution_attempt_guard() OWNER TO intelligence_migrator;
ALTER FUNCTION intelligence.execution_result_attempt_guard() OWNER TO intelligence_migrator;
REVOKE ALL ON FUNCTION intelligence.execution_attempt_guard() FROM PUBLIC;
REVOKE ALL ON FUNCTION intelligence.execution_result_attempt_guard() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION intelligence.execution_attempt_guard() TO intelligence_migrator, intelligence_runtime, intelligence_recovery_admin;
GRANT EXECUTE ON FUNCTION intelligence.execution_result_attempt_guard() TO intelligence_migrator, intelligence_runtime, intelligence_recovery_admin;

ALTER TABLE intelligence.execution_attempts OWNER TO intelligence_migrator;
REVOKE ALL PRIVILEGES ON TABLE intelligence.execution_attempts FROM PUBLIC, intelligence_runtime, intelligence_recovery_admin;
GRANT ALL PRIVILEGES ON TABLE intelligence.execution_attempts TO intelligence_migrator;
GRANT SELECT, INSERT, UPDATE ON TABLE intelligence.execution_attempts TO intelligence_runtime, intelligence_recovery_admin;
ALTER TABLE intelligence.execution_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE intelligence.execution_attempts FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS intelligence_execution_attempts_migrator ON intelligence.execution_attempts;
CREATE POLICY intelligence_execution_attempts_migrator
  ON intelligence.execution_attempts FOR ALL TO intelligence_migrator
  USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS intelligence_execution_attempts_runtime ON intelligence.execution_attempts;
CREATE POLICY intelligence_execution_attempts_runtime
  ON intelligence.execution_attempts FOR ALL TO intelligence_runtime
  USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS intelligence_execution_attempts_recovery ON intelligence.execution_attempts;
CREATE POLICY intelligence_execution_attempts_recovery
  ON intelligence.execution_attempts FOR ALL TO intelligence_recovery_admin
  USING (true) WITH CHECK (true);

DROP TRIGGER IF EXISTS intelligence_execution_attempt_guard ON intelligence.execution_attempts;
CREATE TRIGGER intelligence_execution_attempt_guard
  BEFORE INSERT OR UPDATE OR DELETE ON intelligence.execution_attempts
  FOR EACH ROW EXECUTE FUNCTION intelligence.execution_attempt_guard();

DROP TRIGGER IF EXISTS intelligence_execution_result_attempt_guard ON intelligence.execution_results;
CREATE TRIGGER intelligence_execution_result_attempt_guard
  BEFORE INSERT ON intelligence.execution_results
  FOR EACH ROW EXECUTE FUNCTION intelligence.execution_result_attempt_guard();

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'intelligence_attempt_identity_job_unique'
      AND conrelid = 'intelligence.execution_attempts'::regclass
  ) THEN
    ALTER TABLE intelligence.execution_attempts
      ADD CONSTRAINT intelligence_attempt_identity_job_unique UNIQUE (id, execution_job_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'intelligence_result_identity_job_unique'
      AND conrelid = 'intelligence.execution_results'::regclass
  ) THEN
    ALTER TABLE intelligence.execution_results
      ADD CONSTRAINT intelligence_result_identity_job_unique UNIQUE (id, execution_job_id);
  END IF;
END
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'intelligence_result_attempt_fk'
      AND conrelid = 'intelligence.execution_results'::regclass
  ) THEN
    ALTER TABLE intelligence.execution_results DROP CONSTRAINT intelligence_result_attempt_fk;
  END IF;
  ALTER TABLE intelligence.execution_results
    ADD CONSTRAINT intelligence_result_attempt_fk
    FOREIGN KEY (attempt_id, execution_job_id)
    REFERENCES intelligence.execution_attempts(id, execution_job_id)
    ON DELETE RESTRICT;
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'intelligence_attempt_result_job_fk'
      AND conrelid = 'intelligence.execution_attempts'::regclass
  ) THEN
    ALTER TABLE intelligence.execution_attempts
      ADD CONSTRAINT intelligence_attempt_result_job_fk
      FOREIGN KEY (result_id, execution_job_id)
      REFERENCES intelligence.execution_results(id, execution_job_id)
      ON DELETE RESTRICT;
  END IF;
END
$$;


INSERT INTO intelligence.schema_migrations (version, contract_family, source_lineage)
VALUES (6, 'DRANEKA_INTELLIGENCE_JI_ATTEMPTS_001', 'TRANSITIONAL_NEON_17_23')
ON CONFLICT (version) DO NOTHING;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM intelligence.schema_migrations
    WHERE version = 6
      AND contract_family <> 'DRANEKA_INTELLIGENCE_JI_ATTEMPTS_001'
  ) THEN
    RAISE EXCEPTION 'Draneka Intelligence target migration 6 marker conflicts with DRANEKA_INTELLIGENCE_JI_ATTEMPTS_001';
  END IF;
END
$$;



-- Target migration 7: DRANEKA_INTELLIGENCE_JI_SYSTEM_TRIGGER_GOVERNANCE_001
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM intelligence.schema_migrations
    WHERE version = 6
  ) THEN
    RAISE EXCEPTION 'Required preceding Intelligence migration 6 is not applied';
  END IF;
  IF EXISTS (
    SELECT 1 FROM intelligence.schema_migrations
    WHERE version = 7
      AND contract_family <> 'DRANEKA_INTELLIGENCE_JI_SYSTEM_TRIGGER_GOVERNANCE_001'
  ) THEN
    RAISE EXCEPTION 'Target migration 7 marker conflicts with the admitted contract family';
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS intelligence.system_trigger_admissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trigger_key text NOT NULL,
  event_type text NOT NULL,
  capability_key text NOT NULL,
  status text NOT NULL DEFAULT 'REVOKED',
  policy_version text NOT NULL,
  admitted_by text,
  admitted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT intelligence_system_trigger_status_check CHECK (status IN ('DRAFT', 'ACTIVE', 'REVOKED')),
  CONSTRAINT intelligence_system_trigger_key_nonempty CHECK (btrim(trigger_key) <> ''),
  CONSTRAINT intelligence_system_trigger_event_nonempty CHECK (btrim(event_type) <> ''),
  CONSTRAINT intelligence_system_trigger_capability_nonempty CHECK (btrim(capability_key) <> ''),
  CONSTRAINT intelligence_system_trigger_policy_nonempty CHECK (btrim(policy_version) <> ''),
  CONSTRAINT intelligence_system_trigger_active_metadata CHECK (
    (status = 'ACTIVE' AND admitted_by IS NOT NULL AND btrim(admitted_by) <> '' AND admitted_at IS NOT NULL AND revoked_at IS NULL)
    OR status <> 'ACTIVE'
  ),
  CONSTRAINT intelligence_system_trigger_revoked_metadata CHECK (
    (status = 'REVOKED' AND revoked_at IS NOT NULL)
    OR status <> 'REVOKED'
  ),
  UNIQUE (trigger_key, event_type, policy_version)
);

CREATE OR REPLACE FUNCTION intelligence.system_trigger_admission_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'System trigger admission identity is immutable';
  END IF;
  IF TG_OP = 'INSERT' AND NEW.status = 'REVOKED' AND NEW.revoked_at IS NULL THEN
    NEW.revoked_at := coalesce(NEW.created_at, now());
  END IF;
  IF current_user <> 'intelligence_migrator'
     AND NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = current_user AND rolsuper) THEN
    RAISE EXCEPTION 'System trigger admission changes require the governed migrator authority';
  END IF;
  IF TG_OP = 'UPDATE'
     AND (NEW.id IS DISTINCT FROM OLD.id
       OR NEW.trigger_key IS DISTINCT FROM OLD.trigger_key
       OR NEW.event_type IS DISTINCT FROM OLD.event_type
       OR NEW.capability_key IS DISTINCT FROM OLD.capability_key
       OR NEW.policy_version IS DISTINCT FROM OLD.policy_version
       OR NEW.created_at IS DISTINCT FROM OLD.created_at) THEN
    RAISE EXCEPTION 'System trigger admission identity is immutable';
  END IF;
  IF TG_OP = 'UPDATE'
     AND OLD.status = 'REVOKED'
     THEN
    RAISE EXCEPTION 'Revoked system trigger admission is terminal; issue a new policy version';
  END IF;
  IF NEW.status = 'ACTIVE'
     AND (NEW.admitted_by IS NULL OR btrim(NEW.admitted_by) = '' OR NEW.admitted_at IS NULL OR NEW.revoked_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Active system trigger admission requires actor/time and no revocation time';
  END IF;
  IF NEW.status = 'ACTIVE'
     AND NEW.admitted_by IS DISTINCT FROM current_user THEN
    RAISE EXCEPTION 'Active system trigger admission identity must match the governed database actor';
  END IF;
  IF TG_OP = 'UPDATE'
     AND OLD.status <> 'REVOKED'
     AND NEW.status = 'REVOKED'
     AND NEW.revoked_at IS NULL THEN
    RAISE EXCEPTION 'System trigger revocation requires a revocation time';
  END IF;
  RETURN NEW;
END
$$;

ALTER FUNCTION intelligence.system_trigger_admission_guard() OWNER TO intelligence_migrator;
REVOKE ALL ON FUNCTION intelligence.system_trigger_admission_guard() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION intelligence.system_trigger_admission_guard() TO intelligence_migrator, intelligence_runtime, intelligence_recovery_admin;

ALTER TABLE intelligence.system_trigger_admissions OWNER TO intelligence_migrator;
REVOKE ALL PRIVILEGES ON TABLE intelligence.system_trigger_admissions FROM PUBLIC, intelligence_runtime, intelligence_recovery_admin;
GRANT ALL PRIVILEGES ON TABLE intelligence.system_trigger_admissions TO intelligence_migrator;
GRANT SELECT ON TABLE intelligence.system_trigger_admissions TO intelligence_runtime, intelligence_recovery_admin;
ALTER TABLE intelligence.system_trigger_admissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE intelligence.system_trigger_admissions FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS intelligence_system_trigger_admissions_migrator ON intelligence.system_trigger_admissions;
CREATE POLICY intelligence_system_trigger_admissions_migrator
  ON intelligence.system_trigger_admissions FOR ALL TO intelligence_migrator
  USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS intelligence_system_trigger_admissions_runtime ON intelligence.system_trigger_admissions;
CREATE POLICY intelligence_system_trigger_admissions_runtime
  ON intelligence.system_trigger_admissions FOR SELECT TO intelligence_runtime
  USING (true);
DROP POLICY IF EXISTS intelligence_system_trigger_admissions_recovery ON intelligence.system_trigger_admissions;
CREATE POLICY intelligence_system_trigger_admissions_recovery
  ON intelligence.system_trigger_admissions FOR SELECT TO intelligence_recovery_admin
  USING (true);

DROP TRIGGER IF EXISTS intelligence_system_trigger_admission_guard ON intelligence.system_trigger_admissions;
CREATE TRIGGER intelligence_system_trigger_admission_guard
  BEFORE INSERT OR UPDATE OR DELETE ON intelligence.system_trigger_admissions
  FOR EACH ROW EXECUTE FUNCTION intelligence.system_trigger_admission_guard();


INSERT INTO intelligence.schema_migrations (version, contract_family, source_lineage)
VALUES (7, 'DRANEKA_INTELLIGENCE_JI_SYSTEM_TRIGGER_GOVERNANCE_001', 'TRANSITIONAL_NEON_17_23')
ON CONFLICT (version) DO NOTHING;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM intelligence.schema_migrations
    WHERE version = 7
      AND contract_family <> 'DRANEKA_INTELLIGENCE_JI_SYSTEM_TRIGGER_GOVERNANCE_001'
  ) THEN
    RAISE EXCEPTION 'Draneka Intelligence target migration 7 marker conflicts with DRANEKA_INTELLIGENCE_JI_SYSTEM_TRIGGER_GOVERNANCE_001';
  END IF;
END
$$;



-- Target migration 8: DRANEKA_INTELLIGENCE_JI_BROWSER_RESULT_HANDOFF_001
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM intelligence.schema_migrations
    WHERE version = 7
  ) THEN
    RAISE EXCEPTION 'Required preceding Intelligence migration 7 is not applied';
  END IF;
  IF EXISTS (
    SELECT 1 FROM intelligence.schema_migrations
    WHERE version = 8
      AND contract_family <> 'DRANEKA_INTELLIGENCE_JI_BROWSER_RESULT_HANDOFF_001'
  ) THEN
    RAISE EXCEPTION 'Target migration 8 marker conflicts with the admitted contract family';
  END IF;
END
$$;

ALTER TABLE intelligence.execution_attempts
  ADD COLUMN IF NOT EXISTS browser_result_capability_hash text,
  ADD COLUMN IF NOT EXISTS browser_result_capability_expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS browser_result_capability_used_at timestamptz;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'intelligence_browser_result_capability_hash_nonempty'
      AND conrelid = 'intelligence.execution_attempts'::regclass
  ) THEN
    ALTER TABLE intelligence.execution_attempts
      ADD CONSTRAINT intelligence_browser_result_capability_hash_nonempty
      CHECK (browser_result_capability_hash IS NULL OR btrim(browser_result_capability_hash) <> '');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'intelligence_browser_result_capability_expiry_order'
      AND conrelid = 'intelligence.execution_attempts'::regclass
  ) THEN
    ALTER TABLE intelligence.execution_attempts
      ADD CONSTRAINT intelligence_browser_result_capability_expiry_order
      CHECK (
        browser_result_capability_expires_at IS NULL
        OR claim_expires_at IS NULL
        OR browser_result_capability_expires_at <= claim_expires_at
      );
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'intelligence_browser_result_capability_metadata'
      AND conrelid = 'intelligence.execution_attempts'::regclass
  ) THEN
    ALTER TABLE intelligence.execution_attempts
      ADD CONSTRAINT intelligence_browser_result_capability_metadata
      CHECK (
        browser_result_capability_hash IS NOT NULL
        OR (browser_result_capability_expires_at IS NULL AND browser_result_capability_used_at IS NULL)
      );
  END IF;
END
$$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_intelligence_attempts_browser_result_capability_hash
  ON intelligence.execution_attempts(browser_result_capability_hash)
  WHERE browser_result_capability_hash IS NOT NULL;

CREATE OR REPLACE FUNCTION intelligence.browser_result_capability_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.browser_result_capability_hash IS NOT NULL
     AND NEW.browser_result_capability_hash IS DISTINCT FROM OLD.browser_result_capability_hash THEN
    RAISE EXCEPTION 'Browser result capability identity is immutable';
  END IF;
  IF OLD.browser_result_capability_expires_at IS NOT NULL
     AND NEW.browser_result_capability_expires_at IS DISTINCT FROM OLD.browser_result_capability_expires_at THEN
    RAISE EXCEPTION 'Browser result capability expiry is immutable';
  END IF;
  IF OLD.browser_result_capability_used_at IS NOT NULL
     AND NEW.browser_result_capability_used_at IS DISTINCT FROM OLD.browser_result_capability_used_at THEN
    RAISE EXCEPTION 'Browser result capability consumption is immutable';
  END IF;
  IF NEW.browser_result_capability_used_at IS NOT NULL
     AND OLD.browser_result_capability_used_at IS NULL
     AND pg_has_role(current_user, 'intelligence_runtime', 'member')
     AND current_setting('app.intelligence_work_identity', true) IS DISTINCT FROM OLD.claimed_by THEN
    RAISE EXCEPTION 'Browser result capability consumption requires the current claim owner';
  END IF;
  RETURN NEW;
END
$$;

ALTER FUNCTION intelligence.browser_result_capability_guard() OWNER TO intelligence_migrator;
REVOKE ALL ON FUNCTION intelligence.browser_result_capability_guard() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION intelligence.browser_result_capability_guard() TO intelligence_migrator, intelligence_runtime, intelligence_recovery_admin;

DROP TRIGGER IF EXISTS intelligence_browser_result_capability_guard ON intelligence.execution_attempts;
CREATE TRIGGER intelligence_browser_result_capability_guard
  BEFORE UPDATE ON intelligence.execution_attempts
  FOR EACH ROW EXECUTE FUNCTION intelligence.browser_result_capability_guard();


INSERT INTO intelligence.schema_migrations (version, contract_family, source_lineage)
VALUES (8, 'DRANEKA_INTELLIGENCE_JI_BROWSER_RESULT_HANDOFF_001', 'TRANSITIONAL_NEON_17_23')
ON CONFLICT (version) DO NOTHING;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM intelligence.schema_migrations
    WHERE version = 8
      AND contract_family <> 'DRANEKA_INTELLIGENCE_JI_BROWSER_RESULT_HANDOFF_001'
  ) THEN
    RAISE EXCEPTION 'Draneka Intelligence target migration 8 marker conflicts with DRANEKA_INTELLIGENCE_JI_BROWSER_RESULT_HANDOFF_001';
  END IF;
END
$$;



-- The target ledger records native target migrations, not source migration numbers.
COMMIT;
