# Phase 2 — Event Spine: Results

**Status: PASS (20/20 checks).**

## Object created
`ANALYTICS.EVENT_LOG` — 766 events, one typed shape for the whole timeline:
`event_id, event_time, event_type, business_function, entity_type, entity_id, magnitude, deviation_score,`
`link_{supplier,warehouse,customer,order,shipment}_id, link_region, source_table, source_ref, text_ref`.

| event_type | business_function | rows | magnitude | deviation basis |
|---|---|---|---|---|
| SCHEDULE_CHANGE | SUPPLIER | 4 | NULL | (Phase 4 AI) |
| SHIPMENT_DELAY | SHIPPING | 7 | delay_days | z across all shipments |
| WAREHOUSE_BACKLOG | WAREHOUSE | 366 | backlog_units | z vs per-warehouse 122-day baseline |
| ORDER_DELIVERY | FULFILLMENT | 8 | lateness_days | z across all orders |
| SUPPORT_TICKET | SUPPORT | 8 | NULL | (Phase 4 sentiment) |
| REFUND | FINANCE | 7 | amount | z across all refunds |
| REVENUE | FINANCE | 366 | revenue | z vs per-region 122-day baseline |

## Deviation model (honest by design)
- **Strong statistical signals** come from the daily series: golden WH-WEST backlog peaks at **z = 3.6**; west revenue dip reaches **z = −2.98**; non-event warehouses stay modest (east max z = 1.52).
- **Discrete low-volume events** (shipment, order, refund) carry magnitude + a weaker z (golden shipment z ≈ 0.7, order z ≈ 1.25). These are structurally important but not relied on for statistical anomaly detection — Phase 3+ combines multiple evidence types rather than deviation alone.
- **Doc events** (comm, ticket) have NULL magnitude/deviation here; enriched in Phase 4 via `AI_CLASSIFY` / `SENTIMENT`.

## Link denormalization
Each event carries resolved foreign keys (e.g. support ticket ST-G1 → order OR-G1, warehouse WH-WEST, region west), so Phase 3 candidate-linking is pure SQL on EVENT_LOG with no re-joins.

## Validation (`sql/phase2_tests.sql`)
Per-type counts, event_id uniqueness, no null timestamps, deviation null/non-null by design, golden spike/dip strength thresholds, baseline modesty, all golden events materialized, link-key correctness, and full **temporal ordering** of the golden chain (comm < shipment < backlog < order < ticket < refund < revenue). **All PASS.**

## Next: Phase 3 — Candidate linker (lag windows + allowed transitions + shared-entity joins) producing CANDIDATE_EDGES.
