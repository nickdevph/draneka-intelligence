---
name: draneka-tank-analysis
description: Analyze aquarium and tank questions from Journal Assistant using bounded Journal context, evidence-first reasoning, explicit uncertainty, ranked hypotheses, and the Draneka tank-analysis result contract. Use for water chemistry, livestock behavior or health, compatibility, feeding, cycling, plants, algae, maintenance, equipment, breeding, identification, and unexplained tank events.
metadata:
  draneka-version: "0.1.0"
---

# Draneka Tank Analysis

## Purpose

Use this skill for aquarium/tank-related questions submitted through Journal Assistant when a bounded intelligence analysis is required.

This skill defines **how to analyze**. It does not own Tank, livestock, Journal, case, user, or source-domain records. It must not mutate Journal records, create authoritative facts, or silently convert an inference into a source-domain fact.

## Skill version

`0.1.0`

Every canonical result must record this version. Runtime/platform skill-version identifiers may also exist, but they must not replace Draneka's own semantic version in result provenance.

## Required inputs

The executor should receive, when available:

- the user's current question;
- request/inquiry identifier;
- tank identifier and bounded Tank context;
- current and recent water parameters with timestamps;
- tank volume, temperature, filtration/aeration, substrate, lighting, and relevant equipment;
- livestock and plant records relevant to the question;
- feeding, maintenance, dosing, medication, stocking, and observation history relevant to the question;
- open/recent cases or prior related inquiries;
- relevant user-provided media descriptors or analysis results;
- approved Draneka aquarium knowledge references, if supplied;
- approved external sources, if the execution policy permits external research.

Never invent a missing Tank value. Never assume that an omitted parameter is normal.

## Core reasoning rule

Reason **tank-context-first**.

The task is not to compare the aquarium mechanically with generic care-sheet targets. The task is to explain the user's question using the best available evidence about this specific tank, then use aquarium knowledge to interpret that evidence.

A stable, functioning tank may legitimately differ from generic published ranges. Do not recommend changing a stable parameter solely to make it match a generic target.

## Evidence priority

Apply [the evidence policy](references/evidence-policy.md).

In summary, prefer:

1. current authoritative Journal/Tank records and timestamped measurements;
2. current user observations and supplied media evidence;
3. historical Journal/Tank trends and related records;
4. approved Draneka aquarium knowledge;
5. approved external sources when permitted and materially useful;
6. general model knowledge only when stronger evidence is unavailable.

Conflicts must be surfaced, not silently reconciled.

## Confidence semantics

Confidence measures **evidentiary support and remaining uncertainty**. It does not measure urgency or severity.

Apply the same definitions to finding confidence, hypothesis confidence, and `uncertainty.overall_confidence`:

- `high` — the conclusion is strongly supported by relevant, internally consistent evidence; material conflicts are absent or resolved, and plausible alternatives are unlikely to change the current interpretation. High confidence is not certainty.
- `medium` — meaningful evidence supports the conclusion, but missing data, indirect evidence, unresolved limitations, or plausible alternatives could materially change the interpretation.
- `low` — evidence is limited, indirect, stale, conflicting, or otherwise insufficient for more than a tentative conclusion. Low-confidence conclusions should primarily guide discriminating observation or measurement rather than irreversible intervention, unless a separate safety reason requires precautionary action.

`CONFIDENCE != URGENCY`.

A high-urgency condition may have low confidence when potential harm is serious but the cause is uncertain. A low-urgency conclusion may have high confidence when the evidence is strong and no immediate harm is indicated.

## Analysis workflow

### 1. Classify the inquiry

Assign one or more categories from [the analysis taxonomy](references/analysis-taxonomy.md).

Do not force a single category when the question is genuinely cross-domain.

### 2. Establish the evidence window

Identify which records are relevant to the question and the time period that matters.

Prefer causally relevant evidence over exhaustive context. A feeding question may need recent feeding, livestock, and observations; it normally does not need every historical water test.

### 3. Separate epistemic states

Keep these distinct throughout reasoning and output:

- **Observed** — directly present in authoritative records, current user statements, or directly perceptible supplied media features.
- **Derived** — calculated or summarized from observed evidence, such as a parameter trend.
- **Inferred** — an interpretation or hypothesis supported by evidence but not directly observed.
- **General knowledge** — aquarium knowledge used to interpret the case.
- **Unknown** — missing, stale, contradictory, or unavailable information.

Never phrase an inferred cause as though it were observed. Media evidence may record directly perceptible features; diagnostic, species, or causal interpretation of those features belongs in inference unless independently established.

### 4. Assess data quality

Check for:

- missing measurements;
- stale readings;
- implausible timestamps or units;
- conflicting values;
- uncertain species identification;
- incomplete chronology;
- changes in equipment, stocking, feeding, maintenance, medication, dosing, or temperature that may alter interpretation.

Record material limitations in the result.

### 5. Generate plausible explanations

Produce a bounded set of hypotheses that could explain the question.

For each material hypothesis:

- state the hypothesis;
- state evidence supporting it;
- state evidence against it or reducing its likelihood;
- assign a confidence level using the normative confidence semantics above;
- explain what additional evidence would discriminate it from alternatives when useful.

Do not create a long undifferentiated list of every theoretically possible cause.

### 6. Rank using this tank's evidence

Rank explanations using the available Tank evidence, chronology, and known aquarium mechanisms.

Every hypothesis must have an explicit positive integer `rank`. `rank: 1` is the highest-supported hypothesis. Ranks must be unique and consecutive from `1` through the number of hypotheses, and the hypotheses array must be ordered by ascending rank. Ties are not permitted; if support is effectively tied, use the best-supported ordering available and explain the uncertainty in rationale.

Recent changes temporally linked to the observation should normally receive more weight than unrelated background facts, while still accounting for delayed biological effects where relevant.

### 7. Determine urgency

Use one of:

- `critical` — evidence suggests an immediate risk of livestock loss or severe deterioration and prompt action is warranted;
- `urgent` — material risk exists and action/measurement should occur soon;
- `routine` — no evidence of immediate danger; ordinary investigation or husbandry action is appropriate;
- `low` — primarily informational or optimization-oriented.

Do not label an inquiry critical merely because a generic care guide describes the condition as dangerous. Tie urgency to available evidence.

Urgency is independent from confidence. When potential harm warrants precaution despite uncertain cause, state the lower confidence and the higher urgency separately.

### 8. Recommend bounded actions

Recommendations should be:

- proportional to evidence and urgency;
- reversible where possible;
- specific enough to act on;
- conservative when key information is missing;
- ordered so that observation/measurement comes before intervention when intervention is not yet justified.

Do not recommend rapid parameter chasing in a stable aquarium solely to reach generic target values.

Apply [the safety policy](references/safety-policy.md) before finalizing actions.

### 9. Identify monitoring and missing information

State:

- what the user should monitor;
- what change would increase or decrease concern;
- which missing measurements or observations would materially improve confidence;
- only the follow-up questions that are useful to resolve the analysis.

### 10. Produce the structured result

Return a result that conforms to `schemas/tank-analysis-result.schema.json`.

The executor may additionally produce presentation prose, but the structured result is the canonical machine-readable analysis output.

## Structured evidence invariants

The schema enforces non-empty evidence linkage where Draft 2020-12 can express it. The following semantic invariants are also mandatory for every conforming result and must fail closed at any validating integration boundary:

1. Every evidence `id` is unique within the result.
2. Every finding `basis` reference resolves to exactly one evidence item.
3. Every hypothesis `evidence_for` and `evidence_against` reference resolves to exactly one evidence item.
4. Every recommended-action `basis` reference resolves to exactly one evidence item.
5. Every material finding, hypothesis, and recommended action has a non-empty evidence basis as required by the schema.
6. Hypothesis ranks are unique, consecutive from `1..N`, and array order is ascending by rank.
7. Every external-source provenance `id` is unique.
8. Evidence with `source_class: external_source` has a non-empty `source_ref` that resolves to exactly one `provenance.external_sources[].id`.
9. Use of external-source evidence or the `external_source` knowledge class requires at least one external-source provenance record.

Duplicate identifiers, dangling references, ambiguous references, missing external provenance, or inconsistent ranking make the result non-conforming even if a generic JSON Schema validator cannot express the cross-array constraint.

## Required result principles

Every completed analysis must:

- identify the skill name and version;
- preserve the original question;
- distinguish observations, derived findings, hypotheses, and unknowns;
- identify evidence basis for material conclusions;
- include uncertainty/limitations;
- include urgency;
- include bounded recommended actions when action is warranted;
- include monitoring and follow-up information when useful;
- record knowledge/provenance classes used;
- obey the structured evidence invariants above;
- avoid claiming source-domain mutations occurred.

## Failure / abstention rules

Return an incomplete/low-confidence analysis rather than fabricating evidence when:

- the Tank context package is missing essential information;
- the supplied records conflict materially and the conflict cannot be resolved;
- the question requires evidence not available under the current execution policy;
- species/media identification is too uncertain to support a specific recommendation.

The correct behavior may be to request one or two discriminating measurements/observations rather than to provide a definitive answer.

## Final checks

Before returning:

1. Did I use this Tank's evidence before generic ranges?
2. Did I distinguish observed facts from inference?
3. Did I surface important missing/stale/conflicting data?
4. Are hypotheses explicitly ranked and ordered by support?
5. Are material findings, hypotheses, and actions grounded in non-empty evidence references?
6. Are evidence IDs unique and all references resolvable exactly once?
7. If external knowledge was used, is its provenance complete and linked?
8. Did I apply confidence semantics independently from urgency?
9. Are recommendations proportional, conservative, and reversible where possible?
10. Did I avoid parameter chasing without evidence?
11. Did I comply with the safety policy?
12. Does the structured payload validate against the result schema and semantic invariants?
13. Did I avoid mutating or claiming authority over Journal data?
