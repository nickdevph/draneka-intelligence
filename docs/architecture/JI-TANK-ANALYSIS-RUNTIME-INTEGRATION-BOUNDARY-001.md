# Draneka Tank Analysis — Journal Intelligence Runtime Integration Boundary

- **Boundary record:** `DRANEKA-TANK-ANALYSIS-RUNTIME-BOUNDARY-001`
- **Defined:** 2026-09-11 UTC
- **Canonical skill source:** `nickdevph/draneka-intelligence`
- **Canonical skill commit:** `5ab2012fd7b0bd7ff87e8eb97c1f986b3aedad64`
- **Canonical skill path:** `skills/draneka-tank-analysis`
- **Canonical semantic version:** `0.1.0`
- **Canonical result schema:** `draneka.tank-analysis-result.v1`
- **Current Journal runtime head inspected:** `5e8e24d8560b67ce8d74d310d09854cb97fe495d`
- **Scope:** tank-related Journal Assistant deep-analysis requests only
- **Production mutation in this boundary record:** none

## Authority and current runtime

Journal remains authoritative for Tank, livestock, test, feeding, maintenance, observation, case, and schedule records. Draneka Intelligence remains the intelligence execution lifecycle authority. The Tank Analysis Skill is a versioned reasoning-method contract. A Work executor/provider is replaceable and subordinate to those contracts.

The current path is:

1. an authenticated Journal Assistant request creates a Journal Analysis Request;
2. Journal loads a bounded, owner-scoped Tank context and persists an immutable context binding with a SHA-256 fingerprint;
3. Journal admits a JI execution job and an attempt through the active provider admission;
4. the isolated ChatGPT Work surface claims one attempt without caller-supplied identity selectors;
5. Work creates one append-only artifact in `nickdevph/aquaticfinder-intelligence-work`;
6. the browser result capability submits one result envelope;
7. Journal reconciles the result under a locked owner/request/job/attempt transaction.

This integration adds Tank Skill resolution and canonical-result validation at steps 3, 4, and 7. It does not change Journal source-record ownership or authorize source mutation.

## Eligible route

Only `journal_analysis_requests.analysis_type = TANK_ANALYSIS` and the existing admitted analytical lane receive the Tank Skill projection. Existing deterministic, clarification, unsupported, and non-tank JI routes remain unchanged. The route is selected from the server-owned request and never from an executor-supplied label.

A Tank request is admitted only with:

- the server-owned `analysisRequestId`;
- the server-owned `tankId`;
- the request's current revision and processing cycle;
- a bounded context package returned by the Journal context loader;
- an immutable context binding and fingerprint;
- the existing JI provider admission.

The executor receives no account or Tank identity in its external projection. It reasons only over the supplied bounded context snapshot. The Journal-side locked row remains the authority for routing and custody.

## Exact skill resolution

The runtime representation is an immutable deployment-pinned resolution record:

```json
{
  "contractVersion": "draneka.tank-analysis.skill-resolution.v1",
  "name": "draneka-tank-analysis",
  "version": "0.1.0",
  "sourceRepository": "nickdevph/draneka-intelligence",
  "sourceCommit": "5ab2012fd7b0bd7ff87e8eb97c1f986b3aedad64",
  "packagePath": "skills/draneka-tank-analysis",
  "resultSchemaVersion": "draneka.tank-analysis-result.v1"
}
```

The source commit is the canonical skill admission/merge SHA. The runtime does not resolve a floating branch, tag, or latest file. Any claim or result with a different name, semantic version, source repository, source commit, package path, or result schema version fails closed. A deployment that changes this resolution must be separately reviewed and pinned.

The exact resolution is carried in the private claim and result envelope. It is not inserted into the Tank reasoning schema.

## Context identity

The existing Journal binding is the canonical bounded context identity:

```json
{
  "contractVersion": "draneka.tank-analysis.context-identity.v1",
  "analysisRequestId": "<request id>",
  "requestRevision": 0,
  "processingCycle": 1,
  "contextFingerprint": "<sha256 of canonical bounded context>"
}
```

The fingerprint is calculated by Journal's stable JSON canonicalization over the bounded context package. The package is bounded by the existing loader limits and contains the Journal retrieval/evidence provenance needed for audit. `requestRevision` and `processingCycle` prevent a fingerprint-valid result from being accepted for a later attempt. The executor must not invent or omit a context identity.

## Execution envelope

Provider/runtime facts remain outside `draneka.tank-analysis-result.v1`. The durable JI result envelope contains, in addition to the existing R4 identity:

- execution job, attempt, and analysis request IDs;
- request revision and processing cycle;
- context identity and fingerprint;
- the exact skill resolution;
- ChatGPT Work adapter key/version;
- generic JI result schema version;
- external-research authorization state;
- completion timestamp and validation state;
- append-only GitHub artifact evidence reference;
- the canonical Tank result object.

The initial integration sets external-research authorization to `NOT_AUTHORIZED`. External-source evidence is consequently rejected unless a separately admitted policy explicitly authorizes it and the envelope records that authorization. Provider/model details are provenance only and cannot become Tank facts or Journal authority.

## Acceptance predicates

A submitted Tank result is accepted only when all predicates pass:

```text
JSON_SCHEMA_VALID
AND SEMANTIC_INVARIANTS_VALID
AND SKILL_RESOLUTION_MATCH
AND CONTEXT_IDENTITY_MATCH
AND REQUEST_BINDING_MATCH
AND ACTIVE_ATTEMPT/CURRENT_REQUEST
AND ONE-TIME_CAPABILITY/CLAIM_VALID
AND APPEND_ONLY_ARTIFACT_EVIDENCE_VALID
```

Schema validation must enforce the admitted canonical schema shape, required fields, enums, bounds, conditionals, and exact skill name/version. Semantic validation must additionally enforce:

- unique evidence IDs;
- every finding basis, hypothesis evidence reference, and action basis reference resolves to exactly one evidence item;
- material findings, hypotheses, and actions have non-empty evidence basis;
- hypothesis ranks are unique, consecutive from 1, and equal to ascending array order;
- external evidence has non-empty provenance and an exact single source linkage;
- external provenance IDs are unique and every external source linkage resolves exactly once;
- confidence is one of `high`, `medium`, or `low`, with urgency independent;
- no forbidden authority, credential, or mutation fields.

Invalid schema, semantic, skill, context, request, or currentness results are durably recorded as rejected and never update the Journal Analysis Request to READY. Stale or mismatched submissions fail closed; they are not reconciled to a different request, Tank, user, revision, or attempt.

## Result custody and presentation

The immutable `journal_ji_execution_results.result_envelope` retains the validated canonical Tank result and the execution envelope. The Journal Analysis Request receives its existing owner-facing non-canonical response projection, including the validated summary/findings and provenance pointer, so current Web/Android consumers remain compatible. The projection is presentation only; it does not promote inference to a Journal fact.

The Work artifact remains append-only evidence in `nickdevph/aquaticfinder-intelligence-work`. It contains the generic Work result and the execution source identity/artifact reference required by the current JI contract. It does not become a Journal record.

## Mutation boundary

The Tank Skill, executor, and provider have no Journal write authority. Result reconciliation updates only the JI execution/request lifecycle state under the existing Journal transaction. Any user-approved maintenance, treatment, feeding, stocking, or other action must use a separately authorized Journal operation and its own source-domain semantics. No skill result can write Tank history, livestock facts, measurements, schedules, or cases.

## Failure, retry, replay, and rollback

- A result with a wrong skill or context identity is rejected terminally as an admission/currentness failure.
- A schema or semantic failure is rejected terminally and preserved with bounded validation codes.
- A valid result submitted after request revision, processing cycle, or context change is rejected as stale.
- One-time browser capability and claim checks remain in force; an identical terminal replay may be acknowledged idempotently, while a different terminal result is rejected.
- Lease expiry/recovery remains under the dedicated `journal_recovery_admin` path; the executor cannot requeue or reconcile work.
- The integration is additive and guarded by a single eligible `TANK_ANALYSIS` predicate. Rollback is the prior deployed Journal version and provider admission/configuration, with no destructive migration. Activation is prohibited unless the exact prior deployment and provider admission are recorded immediately before change.
- Observability records IDs, hashes, validation dispositions, and bounded codes only; it does not log account/Tank payloads, credentials, tokens, or hidden reasoning.

## Qualification obligations

Before production adoption, the implementation must demonstrate at merged heads:

1. exact skill resolution and wrong-version rejection;
2. expected context acceptance and stale/mismatch rejection;
3. canonical example schema success;
4. all required semantic adversarial failures;
5. safety cases: healthy high-pH Neocaridina, maintenance distress with missing readings, hazardous current reading, insufficient-data behavior, conflicting readings, juvenile compatibility, successful-history/generic-range conflict, unavailable external research, high urgency plus low confidence, uncertain media, stale measurements, and medication/additive risk;
6. a real non-production Journal Assistant request using its supplied bounded Tank context;
7. correct request/user/Tank readback, durable result custody, append-only Work evidence, safe retry/reconcile behavior, and zero source-record mutation;
8. an independent exact-head implementation review and a reversible production smoke.

## Explicit non-goals

No Journal redesign, Android redesign, Core/Breeder/Customer Ops boundary change, provider replacement, broad Intelligence Inbox, generic aquarium knowledge system, unrelated infrastructure change, or destructive migration is part of this boundary.
