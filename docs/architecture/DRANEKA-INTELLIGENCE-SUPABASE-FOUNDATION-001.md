# Draneka Intelligence — Supabase Foundation 001

Status: **FOUNDER-AUTHORIZED FOUNDATION CANDIDATE — PRODUCTION MUTATION NOT AUTHORIZED**  
Task: `DRANEKA_INTELLIGENCE_SUPABASE_FOUNDATION_001`  
Durable authority: issue #1  
Repository: `nickdevph/draneka-intelligence`

## 1. Objective

Establish the canonical physical and security boundary for Draneka Intelligence on the shared Draneka production Supabase platform without moving live Journal Intelligence traffic yet.

The target physical platform is:

```text
DRANEKA_SHARED_PRODUCTION_PROJECT
→ Supabase AquaticFinder Journal
→ sjodccpuyaasljcunmug
→ eu-west-1
```

The historical project name does **not** make Journal the logical owner of Draneka Intelligence.

Draneka Intelligence remains a first-class peer domain to Journal, Core, Customer Ops, Breeder and future peers.

## 2. Founder-locked ownership boundary

### Draneka Intelligence owns

- intelligence intake lifecycle;
- intelligence request execution lifecycle;
- jobs, attempts and claims;
- provider/work admission;
- bounded execution context custody;
- cancellation, retry, stale-revision and reconciliation semantics;
- result envelopes and result-submission lifecycle;
- execution audit/evidence custody;
- Intelligence Inbox execution state.

### Originating product domains own

- domain meaning;
- source records;
- user-facing product semantics;
- authorization to expose bounded source context to Intelligence.

For Journal specifically, Journal remains authoritative for Tanks, livestock, logs, observations, cases, schedules and Journal records. The Journal Assistant is a Journal-facing integration with Draneka Intelligence, not proof that Intelligence is subordinate to Journal.

## 3. Current production topology — read-only evidence 2026-09-12

### Shared Supabase target

Project `sjodccpuyaasljcunmug` is `ACTIVE_HEALTHY` in `eu-west-1` on PostgreSQL 17.

Current readback shows:

- no `intelligence` schema;
- no canonical Draneka Intelligence request/job/attempt/result tables;
- existing Journal structures remain in `public`;
- `public.journal_tanks` exists and remains Journal-owned;
- `journal_runtime` exists as a NOLOGIN/NOBYPASSRLS role and is **not** the future Intelligence runtime authority.

Existing analysis-named Journal tables such as `public.journal_media_analysis_sessions` are Journal media-domain structures and are not the Draneka Intelligence execution domain.

### Transitional JI production source

```text
PROVIDER = Neon
PROJECT = sparkling-thunder-53335766
BRANCH = br-rapid-bonus-ay2vg3ev
DATABASE = journal_ji_production
STATUS = TRANSITIONAL_PRODUCTION_SOURCE
```

Current exact source row counts:

| Source table | Rows |
|---|---:|
| `journal_analysis_requests` | 8 |
| `journal_ji_analysis_context_bindings` | 6 |
| `journal_ji_deterministic_opportunities` | 0 |
| `journal_ji_deterministic_qualifications` | 0 |
| `journal_ji_execution_jobs` | 6 |
| `journal_ji_execution_attempts` | 5 |
| `journal_ji_execution_results` | 3 |
| `journal_ji_intake_events` | 6 |
| `journal_ji_intake_evidence_items` | 0 |
| `journal_ji_intake_decision_receipts` | 6 |
| `journal_ji_provider_admissions` | 1 |
| `journal_ji_system_trigger_admissions` | 0 |

Source migration lineage is 17–23.

The source additionally contains `journal_tanks` and `schema_state` anchors. Those anchors are not new Draneka Intelligence authorities and must not be copied as ordinary Intelligence-owned domain data.

## 4. Canonical namespace

Draneka Intelligence production persistence will live in a dedicated PostgreSQL schema:

```text
SCHEMA = intelligence
LOGICAL_OWNER = DRANEKA_INTELLIGENCE
PHYSICAL_PROJECT = sjodccpuyaasljcunmug
```

Do not place new Draneka Intelligence execution tables in Journal's `public` namespace merely for convenience.

The `intelligence` schema is a logical-security boundary inside the shared physical project, not a separate Supabase project.

## 5. Role and object-ownership boundary

Target role family:

```text
intelligence_runtime
intelligence_migrator
intelligence_recovery_admin
```

Required properties:

- NOLOGIN by default;
- NOBYPASSRLS;
- NOINHERIT;
- no SUPERUSER / CREATEDB / CREATEROLE / REPLICATION privileges;
- no role memberships into or out of the `intelligence_*` role family are authorized by this foundation;
- explicit schema/table/function grants only;
- no implicit inheritance from `journal_runtime`;
- no use of Journal roles as Intelligence execution authority;
- no direct grants to `anon` or `authenticated` for execution-internal tables;
- no provider credential values stored in ordinary lifecycle rows.

Foundation object-ownership contract:

```text
SCHEMA_OWNER = intelligence_migrator
FOUNDATION_LEDGER_OWNER = intelligence_migrator
FUTURE_INTELLIGENCE_OBJECT_CREATOR = intelligence_migrator
```

The migrator is an administrative DDL identity, not an application runtime identity. Foundation objects use FORCE RLS where applicable so ordinary DML through the migrator identity remains policy-governed even though it owns the objects.

Every future Intelligence migration that creates objects in `intelligence` must create them as `intelligence_migrator` (for example through a separately qualified SET ROLE path). The foundation establishes a creator-role global default privilege that revokes PostgreSQL's PUBLIC EXECUTE default for every future function created by the dedicated `intelligence_migrator` role. PostgreSQL per-schema defaults cannot safely subtract a creator's global function default, so the revocation is deliberately attached to the dedicated creator role rather than only to one schema. Function execution is granted only when an individual migration explicitly requires it.

The application/deployment mechanism that assumes one of these roles must be separately qualified. This document does not authorize credentials, role memberships, or environment-variable changes.

## 6. Compatibility-first target model

Foundation migration is a **custody move first, semantic redesign second**.

The initial Supabase target preserves current lifecycle meaning and identifiers while moving tables into Intelligence ownership. Do not combine the datastore move with a broad multi-producer redesign.

Canonical source→target table mapping:

| Transitional Neon source | Supabase target |
|---|---|
| `public.journal_analysis_requests` | `intelligence.analysis_requests` |
| `public.journal_ji_analysis_context_bindings` | `intelligence.analysis_context_bindings` |
| `public.journal_ji_deterministic_opportunities` | `intelligence.deterministic_opportunities` |
| `public.journal_ji_deterministic_qualifications` | `intelligence.deterministic_qualifications` |
| `public.journal_ji_execution_jobs` | `intelligence.execution_jobs` |
| `public.journal_ji_execution_attempts` | `intelligence.execution_attempts` |
| `public.journal_ji_execution_results` | `intelligence.execution_results` |
| `public.journal_ji_intake_events` | `intelligence.intake_events` |
| `public.journal_ji_intake_evidence_items` | `intelligence.intake_evidence_items` |
| `public.journal_ji_intake_decision_receipts` | `intelligence.intake_decision_receipts` |
| `public.journal_ji_provider_admissions` | `intelligence.provider_admissions` |
| `public.journal_ji_system_trigger_admissions` | `intelligence.system_trigger_admissions` |
| `public.journal_ji_schema_migrations` | **No row-for-row ledger import. Versions 17–23 are evidence lineage only and are preserved through the native target ledger's `source_lineage` field or a separately immutable lineage/evidence receipt.** |

The target `intelligence.schema_migrations.version` namespace is native Draneka Intelligence migration authority. Foundation version `1` is the first native target migration identity. Transitional Neon versions `17–23` must **not** be inserted as target migration versions.

Do not migrate `public.journal_tanks` into `intelligence`.

Do not migrate generic `public.schema_state` as Intelligence payload.

Existing UUIDs, request revisions, processing cycles, idempotency identities, timestamps, context fingerprints, result identities, provider admissions and immutable receipts must be preserved exactly during data migration.

## 7. Journal reference boundary

Current JI rows contain Journal-specific `tank_id` / account references because the existing capability is Journal Tank analysis.

For the first migration:

- preserve those fields and values exactly;
- treat them as source-domain references;
- do not grant Intelligence authority to mutate `public.journal_tanks`;
- validate referenced Tank identity against Journal during qualification;
- do not copy full Journal Tank rows into the Intelligence schema;
- do not introduce hidden cross-domain cascade deletes.

A later separately reviewed multi-producer schema evolution may add neutral producer/subject identifiers. That redesign is not bundled into the foundation migration.

## 8. Source invariants that must survive

The current source already enforces material invariants. Migration must preserve equivalent behavior, including:

- append-only intake events, evidence items, decision receipts and execution results;
- immutable request/job/context/attempt identity fields;
- request idempotency uniqueness;
- one context binding / execution job per request revision and processing cycle;
- ordered attempt sequence and predecessor rules;
- active provider admission requirement for new attempts;
- provider idempotency uniqueness;
- claim-owner checks and claim expiry enforcement;
- result↔attempt↔job identity consistency;
- terminal-attempt immutability;
- immutable provider/system-trigger admission identity and terminal revocation;
- bounded provider projection validation;
- browser-result capability identity/expiry/consumption protections;
- deterministic-opportunity independent-review guard semantics;
- RLS enabled on execution-domain tables.

Names may change to `intelligence_*` equivalents, but behavior must not silently weaken.

## 9. Runtime identity migration

The transitional Neon functions currently key privileged checks to Journal-era identities such as:

```text
journal_runtime
journal_migrator
journal_recovery_admin
app.journal_work_identity
```

The Supabase target must use Intelligence-owned equivalents:

```text
intelligence_runtime
intelligence_migrator
intelligence_recovery_admin
app.intelligence_work_identity
```

Do not preserve Journal role names merely to avoid updating the runtime. Runtime compatibility is a separately qualified phase.

## 10. RLS and exposure model

Initial target contract:

- RLS enabled on all Intelligence lifecycle tables;
- FORCE RLS on foundation-owned append-only ledger objects whose owner is `intelligence_migrator`;
- backend role policies only;
- `anon` = no schema/table access;
- `authenticated` = no direct execution-table access;
- `intelligence_runtime` receives only runtime-required CRUD per table;
- provider/system-trigger admissions and schema metadata are read-only to runtime unless the contract explicitly requires more;
- `intelligence_migrator` owns governed migration/admission effects and is the canonical object creator;
- `intelligence_recovery_admin` receives bounded recovery access;
- PUBLIC receives no direct schema/table privileges and no default EXECUTE on future functions created by the dedicated `intelligence_migrator` creator role;
- service-role/superuser access is not treated as the ordinary runtime contract.

End-user read models, if required, should be exposed through reviewed domain APIs/views rather than direct broad grants to execution internals.

## 11. Migration sequence

```text
1. architecture + source inventory
2. isolated target bootstrap
3. schema/security qualification
4. deterministic data-migration rehearsal
5. repeat/idempotence + digest proof
6. runtime compatibility against target
7. independently reviewed production-target bootstrap
8. bounded writer freeze on transitional Neon
9. final delta migration
10. target readback
11. runtime switch
12. authenticated server + Android E2E
13. rollback window
14. later Neon retirement only under separate authority
```

The one-way boundary occurs only when new production Intelligence writes are admitted to Supabase and can no longer be losslessly reversed by the qualified rollback path.

That gate is not authorized by this foundation PR.

## 12. Rollback principle

Before target writes are admitted, rollback is simple: keep Neon authoritative and discard/revert the unused target bootstrap.

After target writes are admitted, rollback requires a separately proven reverse-delta or dual-custody strategy. Do not claim post-boundary rollback merely because the old Neon database still exists.

Neon remains retained as rollback custody until a later terminal migration decision.

## 13. Qualification gates

Foundation is ready for independent review only when it provides:

```text
SOURCE_INVENTORY = COMPLETE
TARGET_NAMESPACE = DEFINED
ROLE_BOUNDARY = DEFINED
ROLE_DRIFT_FAIL_CLOSED = YES
SCHEMA_LEDGER_DRIFT_FAIL_CLOSED = YES
POLICY_TRIGGER_ACL_RERUN_EXACT = YES
FUTURE_FUNCTION_DEFAULT_EXECUTE_PUBLIC = REVOKED
TABLE_MAPPING = COMPLETE
SOURCE_LINEAGE_17_23 = EVIDENCE_ONLY
JOURNAL_OWNERSHIP_BOUNDARY = DEFINED
SOURCE_INVARIANTS = RECORDED
MIGRATION_SEQUENCE = DEFINED
ROLLBACK_BOUNDARY = DEFINED
PRODUCTION_MUTATION = ZERO
```

The next implementation phase may begin only after fresh independent exact-head review returns PASS.

## 14. Non-authorization

This document does not authorize:

- production Supabase DDL;
- production data import;
- Neon writes, deletion or retirement;
- JI runtime activation or traffic switch;
- environment/credential changes;
- role-assumption membership changes;
- provider change;
- Android modification;
- Journal source-domain writes;
- closure of Android gate #4 or Tank Analysis gate #5.

## 15. Terminal foundation disposition

```text
DRANEKA_INTELLIGENCE_DOMAIN_LEVEL = PEER
SHARED_PHYSICAL_PROJECT = sjodccpuyaasljcunmug
CANONICAL_SCHEMA = intelligence
TRANSITIONAL_JI_SOURCE = NEON
TARGET_ROLE_FAMILY = intelligence_*
CANONICAL_OBJECT_CREATOR = intelligence_migrator
SOURCE_TO_TARGET_MAPPING = DEFINED
SOURCE_LINEAGE_17_23 = EVIDENCE_ONLY
PRODUCTION_DDL = NOT_AUTHORIZED
RUNTIME_CUTOVER = NOT_AUTHORIZED
NEON_RETIREMENT = NOT_AUTHORIZED
NEXT_GATE = FRESH_INDEPENDENT_EXACT_HEAD_REVIEW
```
