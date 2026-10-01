# Phase 5 — Chain Builder: Results

**Status: PASS (17/17 checks). 3 chains reconstructed; golden reconstruction F1 = 1.0.**

## Objects created
- `ANALYTICS.CHAIN_EDGES` — ordered edges per chain (18 rows = 3 chains × 6 steps).
- `ANALYTICS.CHAINS` — one summary row per chain: root/impact, scores, affected entities, earliest signal + intervention.

## Method
1. **best_parent** — per event keep the single highest-evidence *retained* incoming edge (forest, no explosion).
2. **recursive backward walk** from every revenue-impact node to its root.
3. **chosen** — one chain per root = highest-total-evidence path.
4. **CHAINS** summary + earliest signal + earliest intervention.

## Reconstructed chains
| chain | root (earliest signal) | impact | nodes | total score | intervention | lead |
|---|---|---|---|---|---|---|
| CHAIN_SC-G1 (golden) | SUP-ACME comm 2026-09-01 | west revenue dip 2026-09-19 | 7 | 3.83 | SUPPLIER | **18 days** |
| CHAIN_SC-H1 | comm 2026-06-05 | west dip 2026-06-18 | 7 | 3.54 | SUPPLIER | 13 days |
| CHAIN_SC-H2 | comm 2026-07-10 | west dip 2026-07-24 | 7 | 3.60 | SUPPLIER | 14 days |

Golden path (exact order): `SCHEDULE_CHANGE → DELAY → BACKLOG → LATE_DELIVERY → COMPLAINT → REFUND → REVENUE`, edge classes `CAUSAL_STATED → HISTORICAL → HISTORICAL → TEXT → TEXT → HISTORICAL`.

## Earliest intervention (defensible, no overclaim)
Defined as the earliest node that is **observable** AND has a **decision owner** (business_function) — here the supplier schedule-change signal (owner = SUPPLIER/procurement). Presented as *"earliest observable + actionable point"* with a lead-time window (18 days for golden), **not** a counterfactual revenue-saved guarantee.

## Validation (`sql/phase5_tests.sql`)
chains_count=3 · golden root=SC-G1 · impact region=west · node_count=7 · edge_count=6 · all 6 relations present and in order · **golden_false_edges=0** (F1=1.0) · earliest-signal hit on golden + both historical chains · all chains fully supported · no CORRELATION_ONLY in chains · no distractor events in chains · every chain edge is a retained scored edge · intervention function=SUPPLIER with positive lead. **All PASS.**

## Next: Phase 6 — Semantic view + Cortex Agent for natural-language investigation over chains/metrics/evidence.
