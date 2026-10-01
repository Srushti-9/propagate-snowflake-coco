# Phase 3 — Candidate Linker: Results

**Status: PASS (9/9 checks). 156 candidate edges. 100% true-step recall on all 3 chains.**

## Objects created
- `ANALYTICS.LAG_WINDOWS` — the allowed domain transition graph + max lag per step (6 rows), inspectable by UI/agent.
- `ANALYTICS.CANDIDATE_EDGES` — 156 candidate edges (`from/to_event`, types, functions, relation, lag_days/hours, shared entity).

## Candidate rule (observable evidence only — NO causal claim)
An edge A→B is a candidate iff all hold:
1. transition `A.function → B.function` is in `LAG_WINDOWS` (domain plausibility),
2. temporal precedence: A before B within the step's max lag,
3. shared entity along a known key path (supplier/warehouse/order/region),
4. observability gate on daily-series nodes: `|deviation_score| ≥ 1.0` (keeps spikes/dips, drops flat days).

| relation | edges |
|---|---|
| SCHEDULE_CHANGE_PRECEDES_DELAY | 7 |
| DELAY_PRECEDES_BACKLOG | 43 |
| BACKLOG_PRECEDES_LATE_DELIVERY | 50 |
| LATE_DELIVERY_PRECEDES_COMPLAINT | 7 |
| COMPLAINT_ASSOCIATED_WITH_REFUND | 6 |
| REFUNDS_ASSOCIATED_WITH_REVENUE_IMPACT | 43 |

## Design notes
- **Recall-focused by intent.** The linker is permissive; distractors (e.g. SUP-BETA on-schedule comm `SC-D1`, WH-EAST storm order) legitimately appear as candidates. Precision is the job of Phase 4 evidence scoring, not the linker.
- **Gate = 1.0** chosen empirically: golden daily deviation peaks at 2.1–3.6; historical at 1.4–1.5; dips at −1.4 to −3.0. A 1.0 gate keeps all three chains while discarding ~flat baseline days.

## Validation (`sql/phase3_tests.sql`)
golden_recall=6/6 · hist06_recall=6/6 · hist07_recall=6/6 · no backward edges · 0 lag-window violations · no self-loops · no unknown relations · candidate volume in range · distractor candidate present (permissiveness confirmed). **All PASS.**

## Next: Phase 4 — Evidence scorer. Attach the 5 evidence components (temporal, structural, magnitude, textual via Cortex Search, historical) + evidence_class per edge, producing SCORED_EDGES and pruning distractors.
