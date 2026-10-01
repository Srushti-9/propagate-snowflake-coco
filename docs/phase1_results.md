# Phase 1 — Foundation + Synthetic Data: Results

**Status: PASS (30/30 checks).** All objects created in `PROPAGATE` DB.

## Objects created
- Schemas: `CORE`, `DOCS`, `ANALYTICS`
- CORE: `SUPPLIERS`(4), `WAREHOUSES`(3), `CUSTOMERS`(8), `SHIPMENTS`(7), `ORDERS`(8), `REFUNDS`(7), `WAREHOUSE_DAILY`(366), `BUSINESS_METRICS`(366)
- DOCS (MVP 2 sources): `SUPPLIER_COMMS`(4), `SUPPORT_TICKETS`(8)
- ANALYTICS: `GROUND_TRUTH_EDGES`(18 = 3 chains × 6 steps)

## Seeded content
- **GOLDEN_2026_09** — SUP-ACME port-closure comm (2026-09-01) → WH-WEST backlog spike (09-05..09-14, backlog ~1900–2700 vs ~450–570 baseline) → 4 late west orders → 4 negative complaints → 4 LATE_DELIVERY refunds → west revenue dip (09-18..09-25, ~84k vs ~120k baseline).
- **HIST_2026_06 / HIST_2026_07** — smaller analogues of the same chain for recurrence + replay testing.
- **Distractors (absent from ground truth):** on-schedule SUP-BETA comm (SC-D1); unrelated WH-EAST storm-driven late order (OR-D1→ST-D1); non-late DAMAGED refund (RF-D1); praise ticket (ST-D2); east promo revenue blip (09-14..09-18) with correlated timing but no causal link.

## Reproducibility
Generator (`sql/03_seed.sql`) truncates then re-inserts using deterministic formulas only (no `RANDOM`). Re-running yields identical rows and counts.

## Validation (`sql/phase1_tests.sql`)
Row counts, 6 referential-integrity checks (0 orphans), ground-truth id resolution, exactly 1 root + 1 impact per chain, golden spike/dip present, baseline low, distractor present but excluded from ground truth, east promo blip present. **All PASS.**

## CoCo CLI role
All DDL/seed/tests authored as versioned SQL and executed in-account via the agent; no local DB dependencies.

## Next: Phase 2 — Event spine (`ANALYTICS.EVENT_LOG`) + per-entity baselines/deviation scores.
