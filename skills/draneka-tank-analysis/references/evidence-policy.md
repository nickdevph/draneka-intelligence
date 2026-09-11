# Tank Analysis Evidence Policy

## Objective

Make Draneka tank analysis evidence-first, tank-specific, and auditable.

## Evidence classes and precedence

Use the strongest relevant evidence available. The ordering below is a default precedence, not a rule to ignore obvious data-quality problems.

### E1 — Current authoritative Journal/Tank records

Examples:

- timestamped water tests;
- current livestock records;
- current Tank volume/equipment configuration;
- logged maintenance, feeding, dosing, medication, or stocking events;
- active Journal cases and observations.

Treat these as the strongest source-domain evidence when current, internally consistent, and relevant.

### E2 — Current user observation / supplied media evidence

Examples:

- "the shrimp are all at the surface now";
- a newly supplied photograph or video descriptor;
- a user clarification that an event occurred after a water change.

These statements are important case evidence but are not automatically promoted into authoritative Journal records by the analysis skill.

For media, record directly perceptible features as observations. Species, diagnostic, or causal interpretations of those features are inferences unless independently established.

### E3 — Historical Journal/Tank evidence and derived trends

Examples:

- pH stability over several weeks;
- temperature drift;
- repeated nitrate increase before water changes;
- mortality clustered after a stocking event.

Derived trends must be traceable to observed records. Do not fabricate missing points or interpolate silently.

### E4 — Approved Draneka aquarium knowledge

Use curated Draneka knowledge to interpret mechanisms, husbandry, species needs, compatibility, and risk.

Curated knowledge must not override direct Tank evidence without explaining the conflict.

### E5 — Approved external sources

Use external research only when the execution policy permits it and it materially improves the answer. Prefer primary, authoritative, or well-established specialist sources.

Every external source used materially must be recorded in `provenance.external_sources` with a unique stable `id`. Evidence derived from that source must use `source_class: external_source` and set `source_ref` to that exact provenance `id`. If external-source evidence or the `external_source` knowledge class is used, external-source provenance is mandatory.

### E6 — General model knowledge

Use only when stronger evidence or approved references are unavailable. Mark conclusions that materially depend on general model knowledge with appropriate uncertainty.

## Recency and relevance

Evidence strength depends on both source quality and relevance to the event window.

A test from six weeks ago may be authoritative but weak evidence for an acute event today. A user-reported current observation may therefore be more relevant to the immediate question.

Always preserve timestamps when available.

## Conflict handling

If evidence conflicts:

1. identify the conflict;
2. compare timestamp, source authority, unit, method, and context;
3. do not silently choose a convenient value;
4. lower confidence when the conflict remains unresolved;
5. request a discriminating re-measurement or observation when useful.

## Missing-data handling

Never assume an omitted parameter is safe or normal.

Missing data should only block the answer when the missing item is material to the question. Avoid requesting a full water panel when one specific observation or measurement would discriminate the leading hypotheses.

## Generic range handling

Published or learned care ranges are interpretive evidence, not automatic intervention thresholds.

When a tank is stable and livestock evidence is normal, do not recommend altering a parameter solely because it lies outside a commonly quoted generic range. Explain the difference between a generic range and evidence of instability or harm in this Tank.

## Evidence references in output

Material findings, hypotheses, and recommended actions must cite non-empty evidence identifiers supplied in the execution context or locally assigned stable references within the result.

Within one result:

- every evidence `id` must be unique;
- every finding `basis`, hypothesis `evidence_for`/`evidence_against`, and recommended-action `basis` reference must resolve to exactly one evidence item;
- duplicate IDs, dangling references, or ambiguous references are non-conforming and must fail closed;
- every external-source provenance `id` must be unique;
- every `external_source` evidence `source_ref` must resolve to exactly one `provenance.external_sources[].id`.

References must allow a reviewer to determine whether a conclusion came from:

- Journal/Tank data;
- user observation/media;
- derived trend;
- Draneka knowledge;
- external research;
- general model knowledge.
