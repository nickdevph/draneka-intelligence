# Tank Analysis Taxonomy

A tank inquiry may have one or more categories.

## Primary categories

- `water_chemistry` — pH, ammonia, nitrite, nitrate, hardness, alkalinity, salinity, conductivity/TDS, dissolved gases, contaminants, parameter stability.
- `livestock_health` — mortality, injury, visible disease signs, abnormal condition, moulting problems, suspected toxicity.
- `livestock_behavior` — hiding, gasping, surface congregation, inactivity, aggression, schooling changes, unusual movement or feeding response.
- `compatibility_stocking` — species compatibility, stocking density, predation risk, territoriality, life-stage compatibility.
- `feeding_nutrition` — feeding frequency, food choice, competition, underfeeding/overfeeding, supplemental feeding, food-related water-quality effects.
- `cycling_filtration` — biological filtration, cycling state, filter changes, aeration, flow, filterless-system interpretation.
- `plants` — plant health, growth, deficiency-like symptoms, melt, propagation, attachment, CO2/light/nutrient interactions.
- `algae_microfauna` — algae, green water, biofilm, seed shrimp/ostracods, detritivores, microbial blooms and related ecology.
- `maintenance_husbandry` — water changes, cleaning, substrate disturbance, acclimation, quarantine, routine care practices.
- `equipment_environment` — heater, filter, pump, lighting, controller, temperature, flow, electrical/environmental effects.
- `breeding_reproduction` — spawning, pregnancy/gravid state, fry/shrimplet survival, breeding behavior, nursery conditions.
- `identification` — livestock, plant, algae, parasite/pest, egg, juvenile, or media-based identification relevant to a Tank question.
- `event_investigation` — unexplained acute or chronic Tank event requiring multi-factor causal analysis.
- `general_tank_question` — tank-specific inquiry that does not fit a more precise category.

## Cross-category handling

Do not reduce a multi-factor question to a single category merely for routing convenience.

Examples:

- Shrimp at the surface after a water change: `livestock_behavior`, `water_chemistry`, `maintenance_husbandry`, potentially `equipment_environment`.
- Plant melt after medication: `plants`, `maintenance_husbandry`, possibly `water_chemistry`.
- Fry disappearing in a community tank: `breeding_reproduction`, `compatibility_stocking`, `feeding_nutrition`.

## Category is not diagnosis

The taxonomy is for routing and analysis organization. Assigning `livestock_health` does not establish disease; assigning `water_chemistry` does not establish that chemistry caused the event.
