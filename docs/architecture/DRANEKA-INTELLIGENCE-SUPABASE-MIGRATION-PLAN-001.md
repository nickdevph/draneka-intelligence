# Draneka Intelligence — Supabase Migration Plan 001

Status: **FOUNDATION CANDIDATE / NO PRODUCTION EXECUTION AUTHORITY**  
Task: `DRANEKA_INTELLIGENCE_SUPABASE_FOUNDATION_001`  
Depends on: `DRANEKA-INTELLIGENCE-SUPABASE-FOUNDATION-001.md`

## 1. Goal

Move current Journal Intelligence production persistence from the transitional Neon resource into the canonical `intelligence` schema on shared Supabase while preserving behavior, identity, rollback custody and domain ownership.

This plan deliberately separates **foundation**, **rehearsal**, **target bootstrap**, **data cutover**, and **runtime switch** so no documentation merge can accidentally authorize production effects.

Transitional Neon schema migration versions `17–23` are historical source lineage only. They are not target migration identities and must not be copied into the native `intelligence.schema_migrations.version` namespace.

## 2. Phases

### DI-0 — Foundation boundary

Repository-only work.

Deliver:
- target namespace contract;
- role/security boundary;
- exact source inventory;
- source→target mapping;
- source invariant register;
- target bootstrap SQL candidate;
- qualification and rollback matrix.

Required terminal state:

```text
PRODUCTION_MUTATION = ZERO
NEON_MUTATION = ZERO
SUPABASE_PRODUCTION_MUTATION = ZERO
INDEPENDENT_REVIEW = PASS
```

### DI-1 — Isolated target bootstrap

Execute the reviewed target bootstrap only in an isolated non-production database/environment.

Prove:
- `intelligence` schema creation;
- exact `intelligence_*` role attributes and zero unauthorized memberships;
- exact namespace and migration-ledger ownership/ACL/constraint state;
- zero grants to `anon`/`authenticated` on internal tables;
- exact policy and immutable-trigger definitions;
- RLS/FORCE RLS state where defined;
- the dedicated `intelligence_migrator` creator role has a global future-function default privilege revoking PUBLIC EXECUTE (required because per-schema defaults cannot subtract the creator's global function default);
- required table/constraint/index/function/trigger parity;
- runtime role cannot cross-write Journal domain tables;
- Journal runtime cannot assume Intelligence ownership implicitly;
- schema bootstrap is deterministic and repeatable or fails closed on incompatible drift.

No production effects.

### DI-2 — Deterministic data-migration rehearsal

Use a safe isolated target.

Import a deterministic representation of the current production JI dataset or a controlled snapshot/equivalent fixture that preserves the exact relational graph without exposing secrets.

Prove:
- exact row counts;
- stable sorted digest per target table;
- stable aggregate digest;
- PK/FK/reference integrity;
- no orphan request/context/job/attempt/result chain;
- immutable/audit rows retained;
- source migration lineage 17–23 retained as evidence only, never copied into native target migration numbering;
- replay of the same migration is idempotent or explicitly fails closed without divergence;
- no Journal-owned source records are copied as Intelligence authority.

### DI-3 — Runtime compatibility qualification

Adapt runtime code to use Intelligence-owned schema/role identities in an isolated environment.

Qualify:

```text
Journal Assistant request
→ Intelligence analysis request
→ bounded Journal context binding
→ Intelligence job
→ attempt/claim
→ provider/work execution
→ result submission
→ result acceptance
→ Journal-facing projection
```

Required checks:
- global and Tank-scoped Journal Assistant requests;
- owner/account isolation;
- Tank identity isolation;
- idempotent submission;
- unknown-submission recovery;
- current claim-owner enforcement;
- retry and expiry semantics;
- stale revision/context rejection;
- result replay protection;
- source-domain Journal mutations = zero;
- provider-neutrality retained;
- append-only evidence custody retained.

Issue #5 may be used as a downstream runtime qualification gate only after this canonical target/runtime contract exists.

### DI-4 — Production target bootstrap

Separate Founder-authorized operation.

Apply the independently reviewed **empty target** schema/role package to Supabase `sjodccpuyaasljcunmug`.

No live JI data movement and no runtime switch in the same step.

Required readback:
- exact native migration identity;
- exact schema objects;
- exact role attributes/memberships;
- exact ownership/grants/RLS/policies/triggers/default privileges;
- zero accidental grants to peer-domain roles;
- zero Journal data mutation;
- zero current runtime traffic to target.

### DI-5 — Controlled data cutover

Separate Founder-authorized operation.

Preconditions:
- final source row/digest readback;
- source writer inventory complete;
- reversible writer freeze mechanism qualified;
- target empty/expected baseline readback;
- runtime switch package frozen/reviewed;
- pre-boundary rollback tested;
- post-boundary recovery decision explicit.

Execution order:

```text
freeze JI writers
→ snapshot/readback source
→ migrate base+delta
→ target digest + relational checks
→ target security checks
→ runtime switch
→ authenticated server E2E
→ Android E2E gate #4
→ retain Neon rollback custody
```

If any pre-switch verification fails, unfreeze Neon and keep it authoritative.

Do not switch runtime merely because rows imported successfully.

## 3. One-way boundary

The one-way boundary is not target schema creation and not base data import.

The one-way boundary begins when **new authoritative production Intelligence writes are accepted on Supabase** and are not simultaneously covered by a proven reverse-delta mechanism.

Before that boundary:
- Neon remains authoritative;
- target can be discarded/rebuilt;
- rollback is operationally simple.

After that boundary:
- merely keeping Neon online is not lossless rollback;
- reverse-delta or another qualified recovery path is required.

## 4. Data migration order

`intelligence.schema_migrations` is **not** a source data-migration target. The native target ledger is established independently by target migrations, beginning with version `1 = DRANEKA_INTELLIGENCE_SUPABASE_FOUNDATION_001`.

Source `public.journal_ji_schema_migrations` versions `17–23` are retained only as lineage evidence through `source_lineage` or a separately immutable evidence receipt. They are not inserted into the target `version` column.

Recommended dependency-aware data order:

```text
1. provider_admissions
2. system_trigger_admissions
3. analysis_requests
4. analysis_context_bindings
5. intake_events
6. intake_evidence_items
7. intake_decision_receipts
8. deterministic_opportunities
9. deterministic_qualifications
10. execution_jobs
11. execution_attempts
12. execution_results
13. final attempt result references / acceptance state verification
14. source-lineage evidence receipt verification
```

Where cyclic result/attempt FKs make direct insert ordering awkward, use one of these reviewed strategies in rehearsal:
- deferred constraints;
- staged nullable insert followed by governed reconciliation;
- load with constraints created after data then validate;
- deterministic transaction ordering proven against exact source graph.

Do not silently drop cyclic integrity constraints.

## 5. Cross-domain reference strategy

Current source is Journal-specific. Initial migration preserves `tank_id`, account IDs and scope values exactly.

Target rules:
- `public.journal_tanks` remains Journal-owned;
- Intelligence must not gain UPDATE/DELETE grants on Journal Tank tables;
- cross-domain reference validation may use read-only lookup or explicit API qualification;
- avoid `ON DELETE CASCADE` from Journal into Intelligence history;
- archived/deleted source-domain behavior must be deliberate and reviewed;
- a future generic producer/subject reference model is a separate additive migration.

## 6. Security qualification matrix

At minimum prove:

| Actor | Intelligence read | Intelligence write | Journal domain write |
|---|---|---|---|
| `intelligence_runtime` | bounded required | bounded required | NO |
| `intelligence_migrator` | YES | governed migration/admission | NO by default |
| `intelligence_recovery_admin` | governed | governed | NO by default |
| `journal_runtime` | NO implicit ownership | NO | Journal only |
| `authenticated` | NO direct internal-table access | NO | existing Journal policy only |
| `anon` | NO | NO | existing public contract only |

Additional foundation checks:
- all `intelligence_*` roles are NOLOGIN/NOSUPERUSER/NOCREATEDB/NOCREATEROLE/NOINHERIT/NOREPLICATION/NOBYPASSRLS;
- no foundation-authorized role memberships exist into or out of the `intelligence_*` role family;
- `intelligence_migrator` is the canonical schema/object owner and future object creator;
- incompatible pre-existing schema/ledger ownership or structure fails closed;
- known stale grants/policies are converged to the exact allowlist; unknown security state fails closed;
- the immutable ledger trigger is exact in event set, timing and function identity;
- future functions created by the dedicated `intelligence_migrator` role do not inherit PUBLIC EXECUTE, enforced through the creator-role global default privilege;
- service/superuser capabilities are not treated as ordinary application authorization evidence.

## 7. Migration evidence package

Every rehearsal/cutover candidate must record:

```text
SOURCE_PROVIDER
SOURCE_PROJECT
SOURCE_BRANCH
SOURCE_DATABASE
SOURCE_READBACK_TIME
SOURCE_ROW_COUNTS
SOURCE_DIGESTS
SOURCE_SCHEMA_LINEAGE

TARGET_PROVIDER
TARGET_PROJECT
TARGET_SCHEMA
TARGET_MIGRATION_ID
TARGET_ROW_COUNTS
TARGET_DIGESTS
TARGET_ROLE_READBACK
TARGET_ROLE_MEMBERSHIP_READBACK
TARGET_OWNER_ACL_READBACK
TARGET_RLS_READBACK
TARGET_POLICY_READBACK
TARGET_FUNCTION_TRIGGER_READBACK
TARGET_DEFAULT_PRIVILEGE_READBACK

RUNTIME_SOURCE_SHA
RUNTIME_TARGET_IDENTITY
PROVIDER_ADMISSION_IDENTITY

JOURNAL_SOURCE_MUTATIONS
PRODUCTION_EFFECTS
ROLLBACK_DISPOSITION
INDEPENDENT_REVIEW
```

No secrets or credential values in durable receipts.

## 8. Blocking conditions

Stop rather than improvise if:
- source and target schema semantics cannot be reconciled deterministically;
- existing `intelligence_*` roles have incompatible attributes or memberships;
- existing namespace/ledger ownership, shape or ACL state is incompatible and not a specifically recognized convergent prior-candidate state;
- current production writer inventory is incomplete;
- account/Tank ownership cannot be proven;
- provider admission semantics would weaken;
- runtime needs broad `service_role` access as a workaround;
- target requires cross-domain Journal mutation authority;
- post-boundary rollback is falsely assumed rather than proven;
- current PR5/Core→Journal work would be destabilized by the requested effect.

## 9. Relationship to Core → Journal PR5

This programme is intended to remove the JI dependency ambiguity currently visible in Core → Journal PR5.

It must not hijack PR5 or mutate its candidate. Instead it should produce a durable Draneka Intelligence target/runtime qualification that PR5 can consume as dependency evidence.

## 10. Relationship to Android and Tank Analysis gates

Issue #4:
- remains open;
- Android source correction is not presumed;
- authenticated E2E must target the canonical Draneka Intelligence runtime after DI-3/DI-5 qualification.

Issue #5:
- remains a server-side non-production Tank Analysis E2E gate;
- must use canonical Draneka Intelligence lifecycle/runtime once available;
- must not use the legacy processing path as substitute evidence.

## 11. Completion conditions for this plan

Foundation planning is complete when:

```text
NAMESPACE_BOUNDARY = DEFINED
ROLE_BOUNDARY = DEFINED
ROLE_DRIFT_FAIL_CLOSED = YES
SOURCE_INVENTORY = COMPLETE
TABLE_MAPPING = COMPLETE
SOURCE_LINEAGE_17_23 = EVIDENCE_ONLY
SECURITY_MATRIX = DEFINED
MIGRATION_ORDER = DEFINED
ONE_WAY_BOUNDARY = DEFINED
ROLLBACK_MODEL = DEFINED
QUALIFICATION_PHASES = DEFINED
PRODUCTION_MUTATIONS = ZERO
```

Next action after merge: DI-1 isolated bootstrap implementation/rehearsal under a separate bounded commission.
