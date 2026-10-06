-- DRANEKA_INTELLIGENCE_OWNER_ACCOUNT_ERASURE_001
-- Owner-bound Intelligence graph erasure invoked only by Journal's dedicated
-- account-deletion capability. No runtime or recovery role receives DELETE.

BEGIN;

SELECT pg_advisory_xact_lock(hashtext('draneka:intelligence-owner-account-erasure:v1'));

DO $$
BEGIN
  IF current_user <> 'intelligence_migrator'
     AND NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = current_user AND rolsuper) THEN
    RAISE EXCEPTION 'Intelligence owner-account erasure migration requires intelligence_migrator';
  END IF;
  IF to_regclass('intelligence.schema_migrations') IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM intelligence.schema_migrations
       WHERE version = 9
         AND contract_family = 'DRANEKA_INTELLIGENCE_SERVICE_IDENTITIES_001'
     ) THEN
    RAISE EXCEPTION 'Intelligence service identity migration 9 is required';
  END IF;
  IF to_regclass('intelligence.analysis_requests') IS NULL
     OR to_regclass('intelligence.analysis_context_bindings') IS NULL
     OR to_regclass('intelligence.execution_jobs') IS NULL
     OR to_regclass('intelligence.execution_attempts') IS NULL
     OR to_regclass('intelligence.execution_results') IS NULL
     OR to_regclass('intelligence.intake_events') IS NULL
     OR to_regclass('intelligence.intake_evidence_items') IS NULL
     OR to_regclass('intelligence.intake_decision_receipts') IS NULL
     OR to_regclass('intelligence.deterministic_opportunities') IS NULL
     OR to_regclass('intelligence.deterministic_qualifications') IS NULL THEN
    RAISE EXCEPTION 'The complete owner-linked Intelligence graph is required';
  END IF;
  IF NOT EXISTS (
       SELECT 1 FROM pg_roles
       WHERE rolname = 'journal_account_deletion_app'
         AND rolcanlogin AND NOT rolinherit AND NOT rolsuper AND NOT rolcreatedb
         AND NOT rolcreaterole AND NOT rolreplication AND NOT rolbypassrls
     )
     OR NOT EXISTS (
       SELECT 1 FROM pg_roles
       WHERE rolname = 'journal_account_deletion_admin'
         AND NOT rolcanlogin AND NOT rolinherit AND NOT rolsuper AND NOT rolcreatedb
         AND NOT rolcreaterole AND NOT rolreplication AND NOT rolbypassrls
     )
     OR NOT pg_has_role('journal_account_deletion_app', 'journal_account_deletion_admin', 'SET') THEN
    RAISE EXCEPTION 'The dedicated Journal account-deletion capability must be installed first';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'intelligence_migrator' AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication AND NOT rolbypassrls)
     OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'intelligence_runtime' AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication AND NOT rolbypassrls)
     OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'intelligence_recovery_admin' AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication AND NOT rolbypassrls) THEN
    RAISE EXCEPTION 'Intelligence capability roles violate the least-privilege contract';
  END IF;
  IF EXISTS (
    SELECT 1 FROM intelligence.schema_migrations
    WHERE version = 10
      AND contract_family <> 'DRANEKA_INTELLIGENCE_OWNER_ACCOUNT_ERASURE_001'
  ) THEN
    RAISE EXCEPTION 'Intelligence migration 10 marker conflicts with the owner erasure contract';
  END IF;
END
$$;

DO $$
DECLARE
  current_definition text;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO current_definition
  FROM pg_constraint
  WHERE conrelid = 'intelligence.execution_attempts'::regclass
    AND conname = 'execution_attempts_result_id_fkey';
  IF current_definition = 'FOREIGN KEY (result_id) REFERENCES intelligence.execution_results(id) ON DELETE RESTRICT' THEN
    ALTER TABLE intelligence.execution_attempts DROP CONSTRAINT execution_attempts_result_id_fkey;
    ALTER TABLE intelligence.execution_attempts ADD CONSTRAINT execution_attempts_result_id_fkey
      FOREIGN KEY (result_id) REFERENCES intelligence.execution_results(id)
      ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED;
  ELSIF current_definition IS DISTINCT FROM 'FOREIGN KEY (result_id) REFERENCES intelligence.execution_results(id) DEFERRABLE INITIALLY DEFERRED' THEN
    RAISE EXCEPTION 'Unexpected Intelligence attempt result foreign key: %', current_definition;
  END IF;

  SELECT pg_get_constraintdef(oid) INTO current_definition
  FROM pg_constraint
  WHERE conrelid = 'intelligence.execution_attempts'::regclass
    AND conname = 'execution_attempts_predecessor_attempt_id_fkey';
  IF current_definition = 'FOREIGN KEY (predecessor_attempt_id) REFERENCES intelligence.execution_attempts(id) ON DELETE RESTRICT' THEN
    ALTER TABLE intelligence.execution_attempts DROP CONSTRAINT execution_attempts_predecessor_attempt_id_fkey;
    ALTER TABLE intelligence.execution_attempts ADD CONSTRAINT execution_attempts_predecessor_attempt_id_fkey
      FOREIGN KEY (predecessor_attempt_id) REFERENCES intelligence.execution_attempts(id)
      ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED;
  ELSIF current_definition IS DISTINCT FROM 'FOREIGN KEY (predecessor_attempt_id) REFERENCES intelligence.execution_attempts(id) DEFERRABLE INITIALLY DEFERRED' THEN
    RAISE EXCEPTION 'Unexpected Intelligence predecessor foreign key: %', current_definition;
  END IF;

  SELECT pg_get_constraintdef(oid) INTO current_definition
  FROM pg_constraint
  WHERE conrelid = 'intelligence.execution_attempts'::regclass
    AND conname = 'intelligence_attempt_result_job_fk';
  IF current_definition = 'FOREIGN KEY (result_id, execution_job_id) REFERENCES intelligence.execution_results(id, execution_job_id) ON DELETE RESTRICT' THEN
    ALTER TABLE intelligence.execution_attempts DROP CONSTRAINT intelligence_attempt_result_job_fk;
    ALTER TABLE intelligence.execution_attempts ADD CONSTRAINT intelligence_attempt_result_job_fk
      FOREIGN KEY (result_id, execution_job_id)
      REFERENCES intelligence.execution_results(id, execution_job_id)
      ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED;
  ELSIF current_definition IS DISTINCT FROM 'FOREIGN KEY (result_id, execution_job_id) REFERENCES intelligence.execution_results(id, execution_job_id) DEFERRABLE INITIALLY DEFERRED' THEN
    RAISE EXCEPTION 'Unexpected Intelligence attempt/result job foreign key: %', current_definition;
  END IF;

  SELECT pg_get_constraintdef(oid) INTO current_definition
  FROM pg_constraint
  WHERE conrelid = 'intelligence.execution_results'::regclass
    AND conname = 'intelligence_result_attempt_fk';
  IF current_definition = 'FOREIGN KEY (attempt_id, execution_job_id) REFERENCES intelligence.execution_attempts(id, execution_job_id) ON DELETE RESTRICT' THEN
    ALTER TABLE intelligence.execution_results DROP CONSTRAINT intelligence_result_attempt_fk;
    ALTER TABLE intelligence.execution_results ADD CONSTRAINT intelligence_result_attempt_fk
      FOREIGN KEY (attempt_id, execution_job_id)
      REFERENCES intelligence.execution_attempts(id, execution_job_id)
      ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED;
  ELSIF current_definition IS DISTINCT FROM 'FOREIGN KEY (attempt_id, execution_job_id) REFERENCES intelligence.execution_attempts(id, execution_job_id) DEFERRABLE INITIALLY DEFERRED' THEN
    RAISE EXCEPTION 'Unexpected Intelligence result/attempt foreign key: %', current_definition;
  END IF;
END
$$;

DO $$
BEGIN
  IF to_regnamespace('intelligence_internal') IS NULL THEN
    RAISE EXCEPTION 'intelligence_internal schema is required before owner erasure';
  END IF;
  IF (SELECT nspowner FROM pg_namespace WHERE nspname = 'intelligence_internal') <> 'intelligence_migrator'::regrole THEN
    RAISE EXCEPTION 'intelligence_internal schema exists with an unexpected owner';
  END IF;
END
$$;

REVOKE ALL ON SCHEMA intelligence_internal FROM PUBLIC, anon, authenticated, service_role,
  intelligence_runtime, intelligence_recovery_admin, intelligence_recovery_app;
GRANT USAGE ON SCHEMA intelligence_internal TO journal_account_deletion_admin;

CREATE OR REPLACE FUNCTION intelligence_internal.account_erasure_is_authorized(p_owner_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
  SELECT current_user = 'intelligence_migrator'
     AND session_user = 'journal_account_deletion_app'
     AND pg_catalog.pg_has_role(session_user, 'journal_account_deletion_admin', 'member')
     AND p_owner_id IS NOT NULL
     AND pg_catalog.current_setting('app.account_deletion_owner_id', true) = p_owner_id::text
$function$;

ALTER FUNCTION intelligence_internal.account_erasure_is_authorized(uuid) OWNER TO intelligence_migrator;
REVOKE ALL ON FUNCTION intelligence_internal.account_erasure_is_authorized(uuid)
  FROM PUBLIC, anon, authenticated, service_role, intelligence_runtime, intelligence_recovery_admin,
       intelligence_app, intelligence_recovery_app, journal_account_deletion_admin, journal_account_deletion_app;
GRANT EXECUTE ON FUNCTION intelligence_internal.account_erasure_is_authorized(uuid) TO intelligence_migrator;

CREATE OR REPLACE FUNCTION intelligence.reject_append_only_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
  owner_id uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    CASE TG_TABLE_NAME
      WHEN 'intake_events' THEN
        owner_id := OLD.account_id;
      WHEN 'intake_evidence_items' THEN
        SELECT e.account_id INTO owner_id
        FROM intelligence.intake_events e WHERE e.id = OLD.intake_event_id;
      WHEN 'intake_decision_receipts' THEN
        SELECT e.account_id INTO owner_id
        FROM intelligence.intake_events e WHERE e.id = OLD.intake_event_id;
      ELSE
        owner_id := NULL;
    END CASE;
    IF intelligence_internal.account_erasure_is_authorized(owner_id) THEN
      RETURN OLD;
    END IF;
  END IF;
  RAISE EXCEPTION 'Journal Intelligence records are append-only';
END
$function$;

CREATE OR REPLACE FUNCTION intelligence.analysis_request_account_erasure_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  IF TG_OP = 'DELETE'
     AND intelligence_internal.account_erasure_is_authorized(OLD.owner_user_id)
     THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION 'Analysis Requests can only be deleted by exact-owner account erasure'
    USING ERRCODE = '42501';
END
$function$;

CREATE OR REPLACE FUNCTION intelligence.context_binding_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF intelligence_internal.account_erasure_is_authorized(OLD.account_id)
       AND EXISTS (
         SELECT 1 FROM intelligence.analysis_requests r
         WHERE r.id = OLD.analysis_request_id
           AND r.owner_user_id = OLD.account_id
           AND r.tank_id = OLD.tank_id
       ) THEN
      RETURN OLD;
    END IF;
    RAISE EXCEPTION 'Journal Intelligence context bindings require exact-owner account erasure for DELETE'
      USING ERRCODE = '42501';
  END IF;
  IF NEW.analysis_request_id IS DISTINCT FROM OLD.analysis_request_id
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
$function$;

CREATE OR REPLACE FUNCTION intelligence.execution_job_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF intelligence_internal.account_erasure_is_authorized(OLD.account_id)
       AND EXISTS (
         SELECT 1
         FROM intelligence.analysis_requests r
         JOIN intelligence.analysis_context_bindings b ON b.id = OLD.context_binding_id
         WHERE r.id = OLD.analysis_request_id
           AND r.owner_user_id = OLD.account_id
           AND r.tank_id = OLD.tank_id
           AND b.account_id = OLD.account_id
           AND b.analysis_request_id = OLD.analysis_request_id
           AND b.tank_id = OLD.tank_id
           AND b.context_fingerprint = OLD.context_fingerprint
       ) THEN
      RETURN OLD;
    END IF;
    RAISE EXCEPTION 'Journal Intelligence execution jobs require exact-owner account erasure for DELETE'
      USING ERRCODE = '42501';
  END IF;
  IF NEW.analysis_request_id IS DISTINCT FROM OLD.analysis_request_id
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
$function$;

CREATE OR REPLACE FUNCTION intelligence.execution_result_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  IF TG_OP = 'DELETE'
     AND intelligence_internal.account_erasure_is_authorized((
       SELECT j.account_id
       FROM intelligence.execution_jobs j
       JOIN intelligence.analysis_requests r ON r.id = j.analysis_request_id
       WHERE j.id = OLD.execution_job_id
         AND r.owner_user_id = j.account_id
         AND r.tank_id = j.tank_id
     )) THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION 'Journal Intelligence execution results are append-only outside exact-owner account erasure'
    USING ERRCODE = '42501';
END
$function$;

CREATE OR REPLACE FUNCTION intelligence.execution_attempt_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF intelligence_internal.account_erasure_is_authorized((
      SELECT j.account_id
      FROM intelligence.execution_jobs j
      JOIN intelligence.analysis_requests r ON r.id = j.analysis_request_id
      JOIN intelligence.analysis_context_bindings b ON b.id = j.context_binding_id
      WHERE j.id = OLD.execution_job_id
        AND r.owner_user_id = j.account_id
        AND r.tank_id = j.tank_id
        AND b.account_id = j.account_id
        AND b.analysis_request_id = j.analysis_request_id
        AND b.tank_id = j.tank_id
        AND b.context_fingerprint = j.context_fingerprint
    )) THEN
      RETURN OLD;
    END IF;
    RAISE EXCEPTION 'Journal Intelligence execution attempts require exact-owner account erasure for DELETE'
      USING ERRCODE = '42501';
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
         SELECT 1 FROM intelligence.execution_attempts predecessor
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
       SELECT 1 FROM intelligence.execution_results result
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
  IF OLD.claim_token_hash IS NOT NULL AND NEW.claim_token_hash IS DISTINCT FROM OLD.claim_token_hash THEN
    RAISE EXCEPTION 'Journal Intelligence claim token identity is immutable';
  END IF;
  IF OLD.claimed_by IS NOT NULL AND NEW.claimed_by IS DISTINCT FROM OLD.claimed_by THEN
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
$function$;

CREATE OR REPLACE FUNCTION intelligence.deterministic_opportunity_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF intelligence_internal.account_erasure_is_authorized(OLD.account_id) THEN
      RETURN OLD;
    END IF;
    RAISE EXCEPTION 'Deterministic opportunity identity is immutable outside exact-owner account erasure'
      USING ERRCODE = '42501';
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
  IF NEW.status IN ('QUALIFIED', 'ADMITTED') AND current_user <> 'intelligence_migrator' THEN
    RAISE EXCEPTION 'Deterministic opportunity qualification/admission requires the governed migrator authority';
  END IF;
  IF NEW.status IN ('QUALIFIED', 'ADMITTED')
     AND NOT EXISTS (
       SELECT 1 FROM intelligence.deterministic_qualifications q
       WHERE q.opportunity_id = NEW.id
         AND q.verdict = 'PASS'
         AND q.independent_reviewer_ref <> NEW.candidate_actor_ref
     ) THEN
    RAISE EXCEPTION 'Deterministic opportunity admission requires an independent PASS qualification';
  END IF;
  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION intelligence.deterministic_qualification_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
  owner_id uuid;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NOT EXISTS (
      SELECT 1 FROM intelligence.deterministic_opportunities o
      WHERE o.id = NEW.opportunity_id AND o.candidate_actor_ref = NEW.candidate_actor_ref
    ) THEN
      RAISE EXCEPTION 'Deterministic qualification candidate actor does not match its opportunity';
    END IF;
    RETURN NEW;
  END IF;
  IF TG_OP = 'DELETE' THEN
    SELECT o.account_id INTO owner_id
    FROM intelligence.deterministic_opportunities o WHERE o.id = OLD.opportunity_id;
    IF intelligence_internal.account_erasure_is_authorized(owner_id) THEN
      RETURN OLD;
    END IF;
  END IF;
  RAISE EXCEPTION 'Deterministic qualification records are append-only outside exact-owner account erasure'
    USING ERRCODE = '42501';
END
$function$;

CREATE OR REPLACE FUNCTION intelligence_internal.erase_owner_account_data(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF current_user <> 'intelligence_migrator'
     OR session_user <> 'journal_account_deletion_app'
     OR NOT pg_catalog.pg_has_role(session_user, 'journal_account_deletion_admin', 'member')
     OR p_user_id IS NULL
     OR pg_catalog.current_setting('app.account_deletion_owner_id', true) IS DISTINCT FROM p_user_id::text THEN
    RAISE EXCEPTION 'Intelligence erasure requires the dedicated owner-bound Journal account-deletion capability'
      USING ERRCODE = '42501';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM intelligence.analysis_context_bindings b
    JOIN intelligence.analysis_requests r ON r.id = b.analysis_request_id
    WHERE (b.account_id = p_user_id OR r.owner_user_id = p_user_id)
      AND (b.account_id IS DISTINCT FROM r.owner_user_id OR b.tank_id IS DISTINCT FROM r.tank_id)
  ) OR EXISTS (
    SELECT 1
    FROM intelligence.execution_jobs j
    JOIN intelligence.analysis_requests r ON r.id = j.analysis_request_id
    LEFT JOIN intelligence.analysis_context_bindings b ON b.id = j.context_binding_id
    WHERE (j.account_id = p_user_id OR r.owner_user_id = p_user_id)
      AND (j.account_id IS DISTINCT FROM r.owner_user_id OR j.tank_id IS DISTINCT FROM r.tank_id OR b.account_id IS DISTINCT FROM j.account_id
        OR b.analysis_request_id IS DISTINCT FROM j.analysis_request_id OR b.tank_id IS DISTINCT FROM j.tank_id
        OR b.context_fingerprint IS DISTINCT FROM j.context_fingerprint)
  ) THEN
    RAISE EXCEPTION 'Intelligence owner graph has mismatched account, request, or Tank attribution'
      USING ERRCODE = '23514';
  END IF;

  SET CONSTRAINTS
    intelligence.execution_attempts_result_id_fkey,
    intelligence.execution_attempts_predecessor_attempt_id_fkey,
    intelligence.intelligence_attempt_result_job_fk,
    intelligence.intelligence_result_attempt_fk
    DEFERRED;

  DELETE FROM intelligence.deterministic_qualifications q
  USING intelligence.deterministic_opportunities o
  WHERE q.opportunity_id = o.id AND o.account_id = p_user_id;
  DELETE FROM intelligence.deterministic_opportunities WHERE account_id = p_user_id;

  DELETE FROM intelligence.intake_evidence_items i
  USING intelligence.intake_events e
  WHERE i.intake_event_id = e.id AND e.account_id = p_user_id;
  DELETE FROM intelligence.intake_decision_receipts r
  USING intelligence.intake_events e
  WHERE r.intake_event_id = e.id AND e.account_id = p_user_id;
  DELETE FROM intelligence.intake_events WHERE account_id = p_user_id;

  DELETE FROM intelligence.execution_results r
  USING intelligence.execution_jobs j, intelligence.analysis_requests a
  WHERE r.execution_job_id = j.id AND j.analysis_request_id = a.id
    AND j.account_id = p_user_id AND a.owner_user_id = p_user_id;
  DELETE FROM intelligence.execution_attempts a
  USING intelligence.execution_jobs j, intelligence.analysis_requests r
  WHERE a.execution_job_id = j.id AND j.analysis_request_id = r.id
    AND j.account_id = p_user_id AND r.owner_user_id = p_user_id;
  DELETE FROM intelligence.execution_jobs j
  USING intelligence.analysis_requests r, intelligence.analysis_context_bindings b
  WHERE j.analysis_request_id = r.id AND j.context_binding_id = b.id
    AND j.account_id = p_user_id AND r.owner_user_id = p_user_id
    AND b.account_id = p_user_id AND b.analysis_request_id = j.analysis_request_id AND b.tank_id = j.tank_id;
  DELETE FROM intelligence.analysis_context_bindings b
  USING intelligence.analysis_requests r
  WHERE b.analysis_request_id = r.id AND b.account_id = p_user_id
    AND r.owner_user_id = p_user_id AND b.tank_id = r.tank_id;
  DELETE FROM intelligence.analysis_requests WHERE owner_user_id = p_user_id;

  IF EXISTS (SELECT 1 FROM intelligence.analysis_requests WHERE owner_user_id = p_user_id)
     OR EXISTS (SELECT 1 FROM intelligence.analysis_context_bindings WHERE account_id = p_user_id)
     OR EXISTS (SELECT 1 FROM intelligence.execution_jobs WHERE account_id = p_user_id)
     OR EXISTS (SELECT 1 FROM intelligence.intake_events WHERE account_id = p_user_id)
     OR EXISTS (SELECT 1 FROM intelligence.deterministic_opportunities WHERE account_id = p_user_id)
     OR EXISTS (
       SELECT 1 FROM intelligence.execution_attempts a
       JOIN intelligence.execution_jobs j ON j.id = a.execution_job_id
       WHERE j.account_id = p_user_id
     ) OR EXISTS (
       SELECT 1 FROM intelligence.execution_results r
       JOIN intelligence.execution_jobs j ON j.id = r.execution_job_id
       WHERE j.account_id = p_user_id
     ) OR EXISTS (
       SELECT 1 FROM intelligence.intake_evidence_items i
       JOIN intelligence.intake_events e ON e.id = i.intake_event_id
       WHERE e.account_id = p_user_id
     ) OR EXISTS (
       SELECT 1 FROM intelligence.intake_decision_receipts r
       JOIN intelligence.intake_events e ON e.id = r.intake_event_id
       WHERE e.account_id = p_user_id
     ) OR EXISTS (
       SELECT 1 FROM intelligence.deterministic_qualifications q
       JOIN intelligence.deterministic_opportunities o ON o.id = q.opportunity_id
       WHERE o.account_id = p_user_id
     ) THEN
    RAISE EXCEPTION 'Owner-linked Intelligence data could not be fully erased' USING ERRCODE = '23514';
  END IF;
END
$function$;

ALTER FUNCTION intelligence_internal.erase_owner_account_data(uuid) OWNER TO intelligence_migrator;
REVOKE ALL ON FUNCTION intelligence_internal.erase_owner_account_data(uuid)
  FROM PUBLIC, anon, authenticated, service_role, intelligence_runtime, intelligence_recovery_admin,
       intelligence_app, intelligence_recovery_app;
GRANT EXECUTE ON FUNCTION intelligence_internal.erase_owner_account_data(uuid) TO journal_account_deletion_admin;

ALTER FUNCTION intelligence.reject_append_only_mutation() OWNER TO intelligence_migrator;
ALTER FUNCTION intelligence.analysis_request_account_erasure_guard() OWNER TO intelligence_migrator;
ALTER FUNCTION intelligence.context_binding_guard() OWNER TO intelligence_migrator;
ALTER FUNCTION intelligence.execution_job_guard() OWNER TO intelligence_migrator;
ALTER FUNCTION intelligence.execution_result_guard() OWNER TO intelligence_migrator;
ALTER FUNCTION intelligence.execution_attempt_guard() OWNER TO intelligence_migrator;
ALTER FUNCTION intelligence.deterministic_opportunity_guard() OWNER TO intelligence_migrator;
ALTER FUNCTION intelligence.deterministic_qualification_guard() OWNER TO intelligence_migrator;

REVOKE ALL ON FUNCTION intelligence.analysis_request_account_erasure_guard() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION intelligence.analysis_request_account_erasure_guard() TO intelligence_migrator, intelligence_runtime, intelligence_recovery_admin;

DROP TRIGGER IF EXISTS intelligence_analysis_request_account_erasure ON intelligence.analysis_requests;
CREATE TRIGGER intelligence_analysis_request_account_erasure
  BEFORE DELETE ON intelligence.analysis_requests
  FOR EACH ROW EXECUTE FUNCTION intelligence.analysis_request_account_erasure_guard();

INSERT INTO intelligence.schema_migrations (version, contract_family, source_lineage)
VALUES (10, 'DRANEKA_INTELLIGENCE_OWNER_ACCOUNT_ERASURE_001', 'SHARED_SUPABASE_OWNER_BOUND_DELETION')
ON CONFLICT (version) DO NOTHING;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM intelligence.schema_migrations
    WHERE version = 10
      AND (contract_family <> 'DRANEKA_INTELLIGENCE_OWNER_ACCOUNT_ERASURE_001'
        OR source_lineage <> 'SHARED_SUPABASE_OWNER_BOUND_DELETION')
  ) THEN
    RAISE EXCEPTION 'Intelligence migration 10 marker conflicts with owner erasure contract';
  END IF;
END
$$;

COMMIT;
