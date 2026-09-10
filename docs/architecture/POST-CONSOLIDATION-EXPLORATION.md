# Post-Consolidation Intelligence Exploration

Status: PARKED
Trigger: Core → Journal consolidation reaches a suitable qualified terminal state, or Founder explicitly reopens earlier.

## Purpose

This document preserves the questions to explore later without allowing them to interfere with the active consolidation work.

## Parked questions

- Should live Intelligence execution state remain on Neon or move to a dedicated Supabase production datastore?
- What should the Intelligence Inbox own versus expose from Journal, Breeder, and other domains?
- What is the canonical lifecycle for request → job → attempt → claim → analysis → result submission → acceptance → reconciliation?
- Which state is transient, which is durable, and which is authoritative?
- What evidence remains append-only and where should it live?
- How should ChatGPT Work and future providers receive bounded context without broad access to originating-domain databases?
- Should `aquaticfinder-intelligence-work` remain a dedicated evidence/executor repository, become a component of `draneka-intelligence`, or retain another bounded role?
- What production/non-production topology best fits the consolidated platform?
- Where should Supabase branches be used: PR preview, qualification, persistent staging, or other non-production purposes?
- How should full-stack Intelligence E2E tests seed Journal/Breeder context without cloning production customer data?
- How should result routing work when the producer is not Journal?
- What common Intelligence API should producer domains consume without coupling themselves to a specific provider?
- What privacy, TTL, cleanup, deletion, retry, cancellation, stale-revision, idempotency, and reconciliation guarantees are required?

## Explicitly not decided yet

- Supabase versus Neon for live Intelligence execution storage.
- Whether to create a dedicated Supabase project for Intelligence.
- Whether Supabase Branching participates in production Work execution.
- Whether existing JI tables move out of Journal.
- Whether existing repositories are renamed, merged, archived, or superseded.
- Whether the user-facing Journal Assistant/Journal Intelligence naming changes.

## Re-entry criteria

Before implementation planning begins, obtain:

1. the qualified post-consolidation Core/Journal topology;
2. the current live JI architecture and exact interfaces;
3. current provider/work execution evidence and known constraints;
4. current cost/free-tier constraints;
5. a fresh independent architecture review;
6. a migration plan that preserves production continuity and rollback.

Until then, this is an exploration backlog only.
