# Founding Architecture Disposition

Date: 2026-09-10
Status: Founder-authorized architecture record; implementation deferred

## Decision

Draneka Intelligence is established as a **peer platform domain** to Core, Journal, Breeder, and other top-level Draneka domains.

The Intelligence Inbox is a surface/capability **within** Draneka Intelligence rather than a Journal-owned subsystem or the entirety of the Intelligence domain.

## Responsibility split

### Draneka Intelligence owns execution

Future Draneka Intelligence architecture may own:

- intake and Intelligence Inbox mechanics;
- request/job/attempt/claim lifecycle;
- provider/work routing;
- bounded execution context;
- temporary analysis state;
- retry/cancellation/stale-revision handling;
- result-envelope/submission/reconciliation mechanics;
- execution evidence and audit semantics.

### Originating domains own meaning

Journal, Breeder, and other producers retain authority over their source-domain entities and product semantics. Intelligence receives only explicitly authorized bounded context and must not acquire ownership of the underlying Tank, livestock, breeding, case, or other domain records.

Accepted results are routed to the appropriate owning/user-facing domain according to future contracts. Transient analysis state is not authoritative merely because it exists inside Intelligence execution custody.

## Existing JI infrastructure

This disposition is architectural only. It does not authorize migration or redesign of the currently operating Journal Intelligence system.

Existing request/claim/result behavior, worker capability boundaries, append-only evidence mechanisms, production/non-production routing, and repository custody remain in force until separately reviewed and changed.

`aquaticfinder-intelligence-work` is neither superseded nor retired by the creation of `draneka-intelligence`.

## Datastore and branching question

No datastore decision is made here.

After Core → Journal consolidation, the architecture review must compare the current Neon-backed work responsibilities against a possible Supabase-native Intelligence datastore and determine the appropriate production/test/staging split.

Supabase branches may be evaluated for development, preview, qualification, and staging. They are not pre-authorized as the custody mechanism for live production user analysis.

Any future datastore change must preserve bounded execution, privacy, fail-closed environment separation, reconciliation, auditability, and independent production-deployment gates.

## Consolidation dependency

Further Intelligence architecture exploration is parked until Core → Journal consolidation is complete enough that the target platform/database topology is no longer moving underneath the design.

Until that gate is cleared:

- no Intelligence datastore migration;
- no provider migration;
- no JI runtime rewrite;
- no cross-domain Intelligence Inbox rollout;
- no retirement/renaming of existing Intelligence repositories;
- no production infrastructure change arising solely from this disposition.

## Required post-consolidation review

The first fresh review after consolidation should determine:

1. canonical Draneka Intelligence domain model;
2. Intelligence Inbox behavior and UX/product boundary;
3. producer/consumer contracts for Journal, Breeder, and future domains;
4. data classification and retention for request, work, transient analysis, accepted result, and evidence;
5. production datastore and environment topology;
6. Neon/Supabase responsibility convergence, if any;
7. Supabase branch use for test/preview/staging;
8. relationship between `draneka-intelligence` and `aquaticfinder-intelligence-work`;
9. provider-neutral Work execution model;
10. migration and rollback plan if current JI infrastructure is changed.

## Founder gate

```text
DRANEKA_INTELLIGENCE_DOMAIN = ESTABLISHED
PEER_DOMAIN_LEVEL = LOCKED_IN_PRINCIPLE
INTELLIGENCE_INBOX_AS_DOMAIN_SURFACE = LOCKED_IN_PRINCIPLE
IMPLEMENTATION = DEFERRED
ACTIVE_JI_MUTATION = NO
ACTIVE_DATASTORE_MUTATION = NO
NEXT_REVIEW_TRIGGER = CORE_TO_JOURNAL_CONSOLIDATION_COMPLETE_OR_FOUNDER_REOPEN
```
