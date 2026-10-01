# Phase 4 — Evidence Scorer: Results

**Status: PASS (15/15 checks). 156 edges scored; 143 retained, 13 pruned.**

## Objects created
- `ANALYTICS.DOC_SIGNALS` — AI enrichment of every doc: `AI_CLASSIFY` label + `SENTIMENT` + `asserts_cause` flag.
- `DOCS.V_ALL_DOCS` + `DOCS.DOC_SEARCH` — unified docs view and **Cortex Search service** (retrieval surface for the agent + evidence inspection UI).
- `ANALYTICS.SCORED_EDGES` — every candidate edge with 5 components, composite `evidence_score`, `evidence_class`, `retained`.

## Five evidence components (each 0–1, stored for transparency)
`temporal` (lag tightness) · `structural` (key-path strength: order>supplier>warehouse>region) · `magnitude` (endpoint abnormality: z-score, or sentiment/assertion for docs) · `textual` (Cortex `AI_CLASSIFY` of comms/tickets; 0 where no doc) · `historical` (recurrence of the relation on the same entity in other months).

**Weights (explicit, tunable):** textual 0.25, historical 0.25, magnitude 0.20, temporal 0.15, structural 0.15. **Retention threshold 0.40.**

## Evidence class = how much we can claim (causality discipline)
| class | meaning | count | retained |
|---|---|---|---|
| CAUSAL_STATED | a supplier doc explicitly states the cause | 5 | 5 |
| TEXT_SUPPORTED | a document supports the link | 13 | 13 |
| HISTORICAL_SUPPORTED | the relation recurs historically | 129 | 125 |
| TEMPORAL_STRUCTURAL | only timing + shared entity (coincidence-prone) | 9 | **0** |
| CORRELATION_ONLY | weakest | 0 | 0 |

Only explicit supplier statements earn `CAUSAL_STATED`; nothing is called causal from correlation alone.

## AI classification (DOC_SIGNALS)
Disruption comms (SC-G1/H1/H2) → `SCHEDULE_CHANGE_DISRUPTION` (asserts_cause=TRUE); routine SC-D1 → `ROUTINE_NOTICE`. All golden/historical tickets → `LATE_DELIVERY_COMPLAINT` (sentiment −0.71 to −0.89); praise ST-D2 → `PRAISE` (+0.88).

## Golden chain after scoring (all retained)
step1 comm→shipment **CAUSAL_STATED 0.87** · step4 order→ticket TEXT_SUPPORTED 0.65 · step5 ticket→refund TEXT_SUPPORTED 0.59 · step6 refund→revenue 0.58.
**Distractor** on-schedule comm `SC-D1` capped at TEMPORAL_STRUCTURAL **0.38 → dropped**.

## Validation (`sql/phase4_tests.sql`)
all candidates scored · components & score in [0,1] · golden 6/6 retained · step1 is CAUSAL_STATED · CAUSAL_STATED only from asserted comms · on-schedule comm not causal + dropped · all TEMPORAL_STRUCTURAL pruned · no CORRELATION_ONLY retained · pruning occurred · all 3 meaningful classes present · historical component discriminates golden vs distractor. **All PASS.**

## Next: Phase 5 — Chain builder: walk retained edges from an impact node back to the earliest signal -> CHAINS / CHAIN_EDGES, earliest-signal + intervention candidate.
