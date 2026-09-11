# Draneka Intelligence

`draneka-intelligence` is the durable architecture and future implementation custody for **Draneka Intelligence**, a first-class Draneka platform domain at the same architectural level as Core, Journal, Breeder, and other peer product domains.

## Founder disposition

```text
DOMAIN = DRANEKA_INTELLIGENCE
DOMAIN_LEVEL = PEER_TO_CORE_JOURNAL_BREEDER
INTELLIGENCE_INBOX = DOMAIN_SURFACE / CAPABILITY
CURRENT_RUNTIME_MIGRATION = NOT_AUTHORIZED
CURRENT_JI_BEHAVIOR_CHANGE = NOT_AUTHORIZED
CURRENT_PROVIDER_CHANGE = NOT_AUTHORIZED
CURRENT_DATASTORE_CHANGE = NOT_AUTHORIZED
ARCHITECTURE_EXPLORATION = DEFER_UNTIL_CORE_TO_JOURNAL_CONSOLIDATION_FINISHES
BOUNDED_EXCEPTION_2026_09_11 = TANK_ANALYSIS_SKILL_CONTRACT_ONLY
```

## Domain boundary

Draneka Intelligence owns the **execution lifecycle of intelligence work**. This includes, subject to future design and independent review:

- Intelligence Inbox / intake;
- requests, jobs, attempts, and claims;
- provider/work routing;
- bounded execution context;
- transient analysis state;
- cancellation, retry, stale-revision and reconciliation semantics;
- result envelopes and submission lifecycle;
- execution audit/evidence custody.

Originating domains continue to own their own product meaning and authoritative domain records.

Examples:

- Journal owns Tanks, livestock, logs, observations, cases, schedules, and Journal records.
- Breeder owns breeding programs, rounds, pairings, spawn/cohort records, and breeder-specific records.
- Intelligence must not become authoritative for those source-domain entities merely because it analyses them.

A Journal-facing intelligence feature may continue to be presented to users as Journal Intelligence / Journal Assistant. Architecturally, that is a Journal integration with Draneka Intelligence rather than evidence that Intelligence is owned by Journal.

## Intelligence Inbox

The **Intelligence Inbox** is a first-class surface/capability inside Draneka Intelligence. It is not itself the entire domain.

Its future purpose may include receiving bounded work from Journal, Breeder, Vision, Finder, Support/Customer Ops, or other explicitly admitted producers and routing accepted results back to the appropriate user/domain authority.

No cross-domain producer is admitted merely by being named here. Contracts, authorization, privacy boundaries, data minimization, result semantics, and operational ownership remain future gated work.

## Current-state preservation

This repository does **not** supersede or mutate working Journal Intelligence infrastructure merely by existing.

In particular:

- existing JI request/claim/result semantics remain unchanged;
- existing production/non-production infrastructure remains unchanged;
- `aquaticfinder-intelligence-work` is not renamed, repurposed, or retired by this disposition;
- existing append-only evidence/result-artifact custody remains unchanged unless separately authorized;
- no database, Supabase project, Neon project, branch, deployment, provider, credential, Android client, Journal runtime, or production route is changed by this repository initialization.

## Consolidation gate

Architecture exploration and implementation planning for Draneka Intelligence remain generally **deferred until the active Core → Journal consolidation reaches a suitable terminal/qualified state**.

On 2026-09-11 the Founder explicitly authorized one bounded exception: design and durable custody of a versioned Tank Analysis Skill contract for Journal Assistant / ChatGPT Work analysis. This exception does not activate the skill in production and does not authorize JI runtime, datastore, provider, Android, or infrastructure changes. See `docs/architecture/EXPLORATION-GATE.md` and `docs/architecture/TANK-ANALYSIS-SKILL-BOUNDARY.md`.

The consolidation work remains independently governed. This repository must not create a competing migration, datastore, or environment change while that work is active.

After consolidation, a fresh architecture review should examine at minimum:

1. Intelligence Inbox product and operational model.
2. Domain API and producer/consumer contracts for Journal, Breeder, and future peers.
3. Request/job/attempt/result ownership and retention.
4. Temporary ChatGPT Work analysis custody and cleanup semantics.
5. Production datastore choice and whether current Neon responsibilities should remain or converge toward Supabase.
6. Correct use of Supabase production infrastructure versus Supabase branches for test/preview/staging.
7. Relationship between `draneka-intelligence` and `aquaticfinder-intelligence-work`.
8. Provider-neutral worker execution and capability boundaries.
9. Privacy, bounded-context, audit, reconciliation, and failure-recovery requirements.
10. Full-stack test/qualification strategy without production-data cloning.

## Tank Analysis Skill

The initial proposed package lives under `skills/draneka-tank-analysis/` and separates:

- **skill/workflow contract** — how Tank questions must be analyzed;
- **Journal evidence** — what is true about a specific Tank;
- **Draneka aquarium knowledge** — curated domain knowledge used for interpretation;
- **executor/provider** — the replaceable system that performs the analysis;
- **result schema** — the machine-readable output contract.

The package is currently review-only and runtime-inactive.

## Non-negotiable architectural principle

> Intelligence owns intelligence execution; originating product domains own their domain meaning and authoritative records. No transient intelligence execution state becomes authoritative merely because it exists in the Intelligence domain.

## Status

```text
FOUNDING_ARCHITECTURE = RECORDED
GENERAL_INTELLIGENCE_EXPLORATION = DEFERRED_PENDING_CONSOLIDATION
TANK_ANALYSIS_SKILL = PROPOSED / FOUNDER_AUTHORIZED_BOUNDED_DESIGN / INDEPENDENT_REVIEW_REQUIRED
TANK_ANALYSIS_SKILL_RUNTIME = NOT_ACTIVATED
```
