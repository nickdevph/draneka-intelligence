# Draneka Intelligence — Transitional JI Source Inventory 001

Status: **READ-ONLY EVIDENCE**  
Captured: 2026-09-12  
Task: `DRANEKA_INTELLIGENCE_SUPABASE_FOUNDATION_001`

## 1. Source identity

```text
PROVIDER = Neon
PROJECT_ID = sparkling-thunder-53335766
BRANCH_ID = br-rapid-bonus-ay2vg3ev
DATABASE = journal_ji_production
ROLE IN ARCHITECTURE = TRANSITIONAL_PRODUCTION_SOURCE
```

No mutation was performed while collecting this inventory.

## 2. Target identity readback

```text
PROVIDER = Supabase
PROJECT_NAME = AquaticFinder Journal
PROJECT_REF = sjodccpuyaasljcunmug
REGION = eu-west-1
STATUS = ACTIVE_HEALTHY
POSTGRES = 17
ROLE IN ARCHITECTURE = SHARED_DRANEKA_PRODUCTION_PLATFORM
```

Current target readback confirms no `intelligence` schema and no canonical Draneka Intelligence lifecycle tables are present yet.

## 3. Source table inventory and exact row counts

| Table | Exact rows | Target ownership |
|---|---:|---|
| `journal_analysis_requests` | 8 | Intelligence lifecycle |
| `journal_ji_analysis_context_bindings` | 6 | Intelligence lifecycle |
| `journal_ji_deterministic_opportunities` | 0 | Intelligence governance |
| `journal_ji_deterministic_qualifications` | 0 | Intelligence governance |
| `journal_ji_execution_jobs` | 6 | Intelligence execution |
| `journal_ji_execution_attempts` | 5 | Intelligence execution |
| `journal_ji_execution_results` | 3 | Intelligence execution |
| `journal_ji_intake_events` | 6 | Intelligence intake |
| `journal_ji_intake_evidence_items` | 0 | Intelligence intake/evidence |
| `journal_ji_intake_decision_receipts` | 6 | Intelligence intake/audit |
| `journal_ji_provider_admissions` | 1 | Intelligence provider governance |
| `journal_ji_system_trigger_admissions` | 0 | Intelligence trigger governance |
| `journal_ji_schema_migrations` | 7 | migration lineage |

The source also has `journal_tanks` and `schema_state` anchor tables. Those are not ordinary Intelligence-owned payload to copy into the target schema.

## 4. Migration lineage

Current `journal_ji_schema_migrations` entries:

| Version | Contract family |
|---:|---|
| 17 | `R4-C01-C05` |
| 18 | `R4-C06-C09` |
| 19 | `R4-C10-C13` |
| 20 | `R4-C14` |
| 21 | `R4-C15` |
| 22 | `R4-C16` |
| 23 | `R4-C17-BROWSER-RESULT-HANDOFF` |

All were read back with the same applied timestamp in the current production resource.

## 5. Core relationship graph

Current source relationships include:

```text
analysis_request
  ├─ analysis_context_binding
  └─ execution_job
       ├─ execution_attempt
       │    └─ execution_result
       └─ execution_result

intake_event
  ├─ intake_evidence_item
  └─ intake_decision_receipt

provider_admission
  └─ execution_attempt

deterministic_opportunity
  └─ deterministic_qualification
```

Additional source-domain references currently include `tank_id`, `owner_user_id` / `account_id`, scope tokens, request revision, processing cycle and context fingerprints.

## 6. Material source constraints

### Analysis requests

Current source enforces, among other things:

- UUID primary key;
- unique `(owner_user_id, idempotency_key)`;
- request revision > 0;
- fixed analytical lane;
- bounded question and scope-token length;
- allowed request states;
- allowed creation-source values;
- JSON shape checks for originating context, missing information, result and failure;
- 64-character request hash;
- FK from `tank_id` to source `journal_tanks`.

### Context bindings

- UUID primary key;
- unique `(analysis_request_id, request_revision, processing_cycle)`;
- request FK;
- source Tank FK;
- JSON array/object checks for bounded context/evidence/dependency manifests;
- identity is trigger-protected from mutation except invalidation state.

### Execution jobs

- UUID primary key;
- unique `(analysis_request_id, request_revision, processing_cycle)`;
- FK to request and context binding;
- source Tank FK;
- dependency manifest array check;
- bounded status lifecycle;
- identity fields are trigger-protected.

### Execution attempts

- UUID primary key;
- unique `(execution_job_id, attempt_sequence)`;
- unique `provider_idempotency_key`;
- same-job predecessor enforcement;
- active provider-admission requirement;
- claim metadata and expiry enforcement;
- result/attempt/job identity enforcement;
- immutable result, acceptance, claimant and terminal metadata;
- explicit valid state transitions;
- browser-result capability identity/expiry/consumption protection.

### Execution results

- UUID primary key;
- result/job identity uniqueness;
- same-job attempt FK;
- result envelope must be a JSON object;
- append-only after insert;
- insert requires an attempt and, for ordinary runtime, the current claim owner.

### Intake

Intake events, evidence items and decision receipts use unique replay/source identities and are append-only via mutation-rejection triggers.

### Provider and trigger admissions

Provider and system-trigger admission rows enforce:

- immutable identity;
- active/revoked lifecycle metadata;
- terminal revocation;
- governed migrator authority for admission changes;
- safe provider projection shape.

## 7. Source function behavior that must not be lost

Readback found the following JI-specific guard functions in `public`:

- `journal_ji_browser_result_capability_guard`
- `journal_ji_context_binding_guard`
- `journal_ji_deterministic_opportunity_guard`
- `journal_ji_deterministic_qualification_guard`
- `journal_ji_execution_attempt_guard`
- `journal_ji_execution_job_guard`
- `journal_ji_execution_result_attempt_guard`
- `journal_ji_execution_result_guard`
- `journal_ji_provider_admission_guard`
- `journal_ji_provider_projection_is_safe`
- `journal_ji_reject_immutable_mutation`
- `journal_ji_system_trigger_admission_guard`

These functions currently refer to Journal-era database actors such as `journal_runtime`, `journal_migrator`, `journal_recovery_admin` and `app.journal_work_identity`. The target must translate those checks to Intelligence-owned identities rather than preserving Journal role ownership.

## 8. RLS readback

RLS is enabled on:

- `journal_analysis_requests`;
- all current `journal_ji_*` lifecycle/governance tables, including schema migrations.

Current policies are predominantly role-scoped to:

```text
journal_runtime
journal_migrator
journal_recovery_admin
```

Provider/system-trigger admission and migration metadata are more restrictive for ordinary runtime than general execution tables.

The Supabase target must preserve or tighten this posture under `intelligence_*` roles.

## 9. Important indexes

Current source includes dedicated indexes for:

- request owner/update ordering;
- request Tank/state ordering;
- claimable attempts;
- unique browser-result capability hash;
- account/Tank job lookup;
- pending-job dispatch lookup;
- account/intake chronology;
- active provider admission lookup;
- all PK/unique relationship identities.

Target rehearsal must compare required index coverage rather than copying names blindly.

## 10. Target Journal readback

Shared Supabase currently contains `public.journal_tanks` with UUID `id` and Journal-owned `owner_user_id` plus Tank metadata.

The target foundation must not duplicate those rows into `intelligence` or authorize Intelligence writes to Journal Tank state.

## 11. Migration data rule

Data migration must preserve source row identity and value semantics exactly for the first cutover.

At minimum prove:

```text
PRIMARY_KEYS = IDENTICAL
FOREIGN_RELATIONSHIPS = LOSSLESS
REQUEST_REVISIONS = IDENTICAL
PROCESSING_CYCLES = IDENTICAL
IDEMPOTENCY_IDENTITIES = IDENTICAL
CONTEXT_FINGERPRINTS = IDENTICAL
RESULT_IDENTITIES = IDENTICAL
TIMESTAMPS = IDENTICAL
PROVIDER_ADMISSIONS = IDENTICAL
IMMUTABLE_RECEIPTS = IDENTICAL
ROW_COUNTS = IDENTICAL
REPEAT_DIGEST = STABLE
```

Any future multi-producer generalization must be an additive/reviewed schema evolution, not an undocumented transformation during this custody move.

## 12. Inventory disposition

```text
SOURCE_INVENTORY = COMPLETE_FOR_FOUNDATION_BOUNDARY
SOURCE_MUTATION = ZERO
TARGET_MUTATION = ZERO
SOURCE_DATASET_SIZE = SMALL
SOURCE_LINEAGE = 17..23
NEXT_USE = TARGET_BOOTSTRAP + MIGRATION REHEARSAL DESIGN
```
