# Tank Analysis Skill — Initial Acceptance Evals

These are behavioral acceptance cases for `draneka-tank-analysis` v0.1.0. They are not intended to encode one exact prose answer.

A result is accepted only when it satisfies both the Draft 2020-12 JSON Schema and the mandatory semantic invariants in `SKILL.md`. Cross-array uniqueness and referential-integrity rules that generic JSON Schema cannot express must be enforced by semantic validation at an integration boundary and are treated as fail-closed requirements here.

## EVAL-001 — Stable high pH, healthy Neocaridina

### Input

- Tank has Neocaridina.
- pH history is 8.0–8.2 over several weeks.
- Current pH is 8.1.
- Recent observations show normal feeding and moulting; no mortality.
- User asks whether to lower pH because a generic source quotes a lower ideal range.

### Must

- prioritize tank stability over generic target chasing;
- identify the pH trend as stable;
- avoid representing generic range mismatch as proof of harm;
- avoid recommending active pH reduction solely to hit a target;
- mark urgency `low` or `routine`;
- explain what evidence would justify reassessment.

### Must not

- claim pH 8.1 is automatically dangerous;
- invent GH/KH/TDS values;
- recommend an abrupt chemistry change.

## EVAL-002 — Shrimp congregating near the surface after maintenance

### Input

- User reports shrimp moved toward the surface shortly after a substantial maintenance event.
- No current dissolved oxygen reading is available.
- Current ammonia/nitrite readings are absent.
- Temperature reading is current and ordinary for this Tank.

### Must

- classify as at least `livestock_behavior` + `event_investigation` and consider water/oxygenation/maintenance categories;
- identify the temporal link to maintenance as relevant evidence, not proof of cause;
- rank a small number of plausible hypotheses;
- explicitly state missing discriminating measurements/observations;
- recommend low-risk verification/mitigation appropriate to the evidence;
- use `insufficient_data_for_intervention` and/or relevant risk flags when justified.

### Must not

- diagnose one cause with high confidence from surface behavior alone;
- fabricate water-test results.

## EVAL-003 — Acute abnormal behavior with a current hazardous reading

### Input

- Current timestamped Journal reading indicates a materially unsafe nitrogen-cycle value.
- Fish are actively showing respiratory distress.
- A recent filter disruption is recorded.

### Must

- assign high weight to the current reading and distress;
- classify as `critical` or `urgent` based on the complete supplied evidence;
- distinguish immediate mitigation from long-term filter/cycle investigation;
- cite the actual evidence supporting urgency;
- avoid diluting the answer with low-priority generic husbandry advice.

## EVAL-004 — Fish hiding; evidence insufficient

### Input

- User asks why a fish is hiding.
- Tank context contains species and tank size but no recent observations, water readings, stocking change, lighting change, or aggression evidence.

### Must

- avoid pretending a cause is known;
- provide a bounded hypothesis set;
- give low overall confidence;
- request only the most useful discriminating observations or measurements;
- return a useful analysis without requiring every possible parameter.

## EVAL-005 — Conflicting temperature evidence

### Input

- Journal sensor record reports one temperature.
- User reports a different handheld reading taken at approximately the same time.
- The difference is large enough to affect interpretation.

### Must

- surface the conflict explicitly;
- avoid silently choosing one value;
- lower confidence;
- recommend verification of the discrepancy before temperature-specific intervention unless other evidence creates urgency.

## EVAL-006 — Compatibility question involving vulnerable juveniles

### Input

- User asks whether a proposed fish is compatible with an established shrimp tank containing shrimplets.
- Adult water conditions may overlap, but predation risk for juveniles is material.

### Must

- distinguish adult coexistence from shrimplet safety;
- analyze behavior/predation and life stage, not water parameters alone;
- avoid treating "survival" as equivalent to appropriate long-term compatibility.

## EVAL-007 — Generic care range conflicts with successful tank history

### Input

- A species has been stable long-term in a Tank with a parameter slightly outside a commonly cited range.
- No distress trend is present.
- User asks whether to alter the parameter.

### Must

- identify the generic range as interpretive knowledge rather than an automatic intervention threshold;
- preserve uncertainty about long-term species-specific risk if evidence warrants it;
- avoid recommending change solely because of the range mismatch.

## EVAL-008 — External research unavailable

### Input

- The question concerns a niche species detail not present in supplied Journal context or approved Draneka knowledge.
- External research is not permitted in this run.

### Must

- state the limitation;
- avoid fabricating species-specific facts;
- either answer at a more general evidence-supported level or abstain from the unsupported part;
- record `general_model` only if general model knowledge is actually used.

## EVAL-009 — High urgency with low confidence

### Input

- Multiple livestock are suddenly distressed.
- The only current evidence is a user observation and a recent major maintenance event.
- Current ammonia, nitrite, dissolved oxygen, and temperature measurements are unavailable.
- The potential consequence of delaying basic verification/low-risk mitigation is serious, but the cause is not established.

### Must

- allow `urgent` or `critical` urgency when justified by potential harm;
- use `low` confidence for causal hypotheses and overall confidence unless stronger evidence exists;
- explicitly state that confidence measures evidentiary support while urgency measures time-sensitive risk;
- recommend conservative, reversible verification/mitigation rather than a cause-specific irreversible intervention.

### Must not

- raise confidence merely because urgency is high;
- lower urgency solely because the cause is uncertain.

## EVAL-010 — Evidence grounding and referential integrity

### Invalid subcases

Each of the following must be rejected as non-conforming:

1. a finding with `basis: []`;
2. a hypothesis with `evidence_for: []`;
3. a recommended action with `basis: []`;
4. two evidence items with the same `id`;
5. a finding/action/hypothesis reference to an evidence ID that does not exist.

### Expected enforcement

- empty finding/action/hypothesis support arrays: `REJECTED_BY_SCHEMA`;
- duplicate evidence IDs: `REJECTED_BY_SEMANTIC_VALIDATION`;
- dangling evidence references: `REJECTED_BY_SEMANTIC_VALIDATION`.

No consumer may treat a schema-valid payload with duplicate or unresolved references as conforming.

## EVAL-011 — Deterministic hypothesis ranking

### Input

- Three bounded hypotheses are supported to different degrees by the available Tank evidence.

### Must

- assign explicit ranks `1`, `2`, and `3`;
- place the highest-supported hypothesis at rank `1`;
- keep ranks unique and consecutive;
- order the hypotheses array by ascending rank;
- preserve confidence as a separate field rather than deriving confidence mechanically from rank.

### Invalid subcases

The following are non-conforming and must fail semantic validation:

- duplicate ranks;
- skipped ranks such as `1, 3`;
- array order inconsistent with rank.

## EVAL-012 — External-source provenance linkage

### Passing subcase

- external research is permitted and materially used;
- the result includes `external_source` in `provenance.knowledge_classes_used`;
- `provenance.external_sources` contains at least one record with a unique `id`, title, reference, and retrieval time when available;
- every evidence item with `source_class: external_source` has `source_ref` equal to exactly one external-source provenance `id`.

This result must pass schema validation and semantic linkage validation.

### Invalid subcases

Each of the following must be rejected:

1. external-source evidence exists but `provenance.external_sources` is absent;
2. external-source evidence exists but `provenance.external_sources` is empty;
3. `external_source` is listed in `knowledge_classes_used` but external provenance is absent/empty;
4. external-source evidence has a missing/null/empty `source_ref`;
5. external-source evidence `source_ref` does not match exactly one external-source provenance `id`;
6. duplicate external-source provenance IDs make linkage ambiguous.

### Expected enforcement

- absent/empty provenance when external use is declared: `REJECTED_BY_SCHEMA`;
- missing/null/empty external `source_ref`: `REJECTED_BY_SCHEMA`;
- unresolved or duplicate external provenance linkage: `REJECTED_BY_SEMANTIC_VALIDATION`.

## Cross-eval acceptance checks

Every successful result must:

- identify skill version `0.1.0`;
- preserve source-domain authority boundaries;
- distinguish observation/derivation/inference/unknowns;
- use the normative high/medium/low confidence definitions independently from urgency;
- avoid unsupported certainty;
- use explicit unique/consecutive hypothesis ranks;
- give material findings, hypotheses, and recommended actions non-empty evidence support;
- use unique evidence IDs and resolvable references;
- preserve mandatory external-source provenance and linkage when external knowledge is used;
- conform to `schemas/tank-analysis-result.schema.json` and the semantic invariants in `SKILL.md`;
- not claim that Journal records were changed.
