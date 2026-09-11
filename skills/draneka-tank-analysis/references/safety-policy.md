# Tank Analysis Safety Policy

## Purpose

Keep recommendations proportionate to the evidence and avoid harm from unnecessary or abrupt aquarium interventions.

## General principles

1. Prefer measurement and observation before intervention when there is no evidence of immediate danger.
2. Prefer reversible, incremental actions over abrupt environmental changes.
3. Do not recommend changing a stable parameter solely to match a generic target range.
4. Do not present a disease, toxin, deficiency, or causal mechanism as confirmed unless the evidence supports that certainty.
5. Avoid recommending several simultaneous changes when doing so would make cause and effect impossible to interpret, unless immediate risk clearly justifies action.
6. Distinguish routine husbandry suggestions from urgent risk-control actions.

## Water and environmental changes

When recommending a material change to water conditions, temperature, aeration, flow, lighting, feeding, or other husbandry conditions:

- explain why the change is warranted for this Tank;
- account for current livestock and observed stability;
- prefer gradual correction unless evidence indicates an acute threat;
- do not invent missing measurements, quantities, product details, or target values;
- call out uncertainty when measurement method, units, or current conditions are unclear.

## Acute risk

Evidence of dangerous water conditions, oxygenation problems, contamination, extreme temperature, or comparable acute risk may justify prompt bounded action.

The analysis must identify the evidence creating urgency and distinguish immediate mitigation from longer-term remediation.

## Products, treatments, and additives

Do not provide a specific treatment quantity or product-specific instruction unless the necessary Tank facts and product information are present and trustworthy.

When compatibility, formulation, or required context is unknown, recommend verification rather than guessing.

## Livestock health uncertainty

Visible signs and behavior often have overlapping causes. Preserve a differential/hypothesis model where appropriate.

Recommend specialist aquatic veterinary or experienced local professional evaluation when evidence indicates severe, persistent, unexplained, or rapidly worsening illness and remote analysis cannot responsibly discriminate the cause.

## Compatibility

Do not interpret "can survive" as "appropriate long-term husbandry." Consider adult size, behavior, predation, group requirements, water conditions, and vulnerable life stages such as fry or shrimplets.

## Media-based identification

Images or video may support identification but can be ambiguous. Do not claim definitive species, disease, parasite, sex, or deficiency identification when visual evidence is insufficient.

## High-uncertainty response

When confidence is low and intervention could create material risk, prefer to:

1. state what is known;
2. state the leading possibilities;
3. request the smallest useful additional measurement or observation;
4. provide only low-risk interim actions, if any.

## Safety flags

Use relevant flags in structured output when justified:

- `acute_water_quality_risk`
- `oxygenation_risk`
- `temperature_risk`
- `contamination_risk`
- `rapid_parameter_change_risk`
- `treatment_or_additive_risk`
- `livestock_distress`
- `predation_or_compatibility_risk`
- `insufficient_data_for_intervention`

Absence of a flag does not prove absence of risk; it means no flag was justified by the analyzed evidence.
