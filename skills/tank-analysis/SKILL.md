---
name: draneka-tank-analysis
description: Analyze aquarium tank questions using bounded Journal context, evidence-first reasoning, explicit uncertainty, and the Draneka tank-analysis result contract.
version: 0.1.0
---

# Draneka Tank Analysis

## Purpose

Use this skill for aquarium/tank-related questions submitted through Journal Assistant when a bounded intelligence analysis is required.

This skill defines **how to analyze**. It does not own Tank, livestock, Journal, case, user, or source-domain records. It must not mutate Journal records, create authoritative facts, or silently convert an inference into a source-domain fact.

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

Apply `references/evidence-policy.md`.

In summary, prefer:

1. current authoritative Journal/Tank records and timestamped measurements;
2. current user observations and supplied media evidence;
3. historical Journal/Tank trends and related records;
4. approved Draneka aquarium knowledge;
5. approved external sources when permitted and materially useful;
6. general model knowledge only when stronger evidence is unavailable.

Conflicts must be surfaced, not silently reconciled.

## Analysis workflow

### 1. Classify the inquiry

Assign one or more categories from `references/analysis-taxonomy.md`.

Do not force a single category when the question is genuinely cross-domain.

### 2. Establish the evidence window

Identify which records are relevant to the question and the time period that matters.

Prefer causally relevant evidence over exhaustive context. A feeding question may need recent feeding, livestock, and observations; it normally does not need every historical water test.

### 3. Separate epistemic states

Keep these distinct throughout reasoning and output:

- **Observed** — directly present in authoritative records, current user statements, or supplied media evidence.
- **Derived** — calculated or summarized from observed evidence, such as a parameter trend.
- **Inferred** — an interpretation or hypothesis supported by evidence but not directly observed.
- **General knowledge** — aquarium knowledge used to interpret the case.
- **Unknown** — missing, stale, contradictory, or unavailable information.

Never phrase an inferred cause as though it were observed.

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
- assign a confidence level;
- explain what additional evidence would discriminate it from alternatives when useful.

Do not create a long undifferentiated list of every theoretically possible cause.

### 6. Rank using this tank's evidence

Rank explanations using the available Tank evidence, chronology, and known aquarium mechanisms.

Recent changes temporally linked to the observation should normally receive more weight than unrelated background facts, while still accounting for delayed biological effects where relevant.

### 7. Determine urgency

Use one of:

- `critical` — evidence suggests an immediate risk of livestock loss or severe deterioration and prompt action is warranted;
- `urgent` — material risk exists and action/measurement should occur soon;
- `routine` — no evidence of immediate danger; ordinary investigation or husbandry action is appropriate;
- `low` — primarily informational or optimization-oriented.

Do not label an inquiry critical merely because a generic care guide describes the condition as dangerous. Tie urgency to available evidence.

### 8. Recommend bounded actions

Recommendations should be:

- proportional to evidence and urgency;
- reversible where possible;
- specific enough to act on;
- conservative when key information is missing;
- ordered so that observation/measurement comes before intervention when intervention is not yet justified.

Do not recommend rapid parameter chasing in a stable aquarium solely to reach generic target values.

Apply `references/safety-policy.md` before finalizing actions.

### 9. Identify monitoring and missing information

State:

- what the user should monitor;
- what change would increase or decrease concern;
- which missing measurements or observations would materially improve confidence;
- only the follow-up questions that are useful to resolve the analysis.

### 10. Produce the structured result

Return a result that conforms to `schemas/tank-analysis-result.schema.json`.

The executor may additionally produce presentation prose, but the structured result is the canonical machine-readable analysis output.

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
4. Are hypotheses ranked rather than merely listed?
5. Are recommendations proportional, conservative, and reversible where possible?
6. Did I avoid parameter chasing without evidence?
7. Did I comply with the safety policy?
8. Does the structured payload validate against the result schema?
9. Did I avoid mutating or claiming authority over Journal data?
