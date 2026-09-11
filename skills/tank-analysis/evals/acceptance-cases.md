# Tank Analysis Skill — Initial Acceptance Evals

These are behavioral acceptance cases for `draneka-tank-analysis` v0.1.0. They are not intended to encode one exact prose answer.

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

## Cross-eval acceptance checks

Every successful result must:

- identify skill version `0.1.0`;
- preserve source-domain authority boundaries;
- distinguish observation/derivation/inference/unknowns;
- avoid unsupported certainty;
- make evidence references traceable;
- conform to `schemas/tank-analysis-result.schema.json`;
- not claim that Journal records were changed.
