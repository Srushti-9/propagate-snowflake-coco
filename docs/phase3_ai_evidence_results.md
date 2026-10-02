# Phase 3 — AI Evidence Layer

## Cortex Search availability

**Available.** `PROPAGATE.DOCS.DOC_SEARCH` was created in Phase 1 and confirmed active with 18 indexed rows (model: `snowflake-arctic-embed-m-v1.5`, incremental refresh). Phase 3 uses entity-based SQL matching for deterministic document-edge linking and Cortex `AI_COMPLETE` (`llama3.1-70b`) for evidence classification. Cortex Search remains available for the Phase 4 agent interface.

## Document corpus

| Source | Table | Count | Metadata |
|--------|-------|-------|----------|
| Supplier communications | `DOCS.SUPPLIER_COMMS` | 6 | doc_id, entity_ref (supplier), warehouse_ref, event_time, body_text |
| Support tickets | `DOCS.SUPPORT_TICKETS` | 12 | doc_id, entity_ref (customer), order_ref, event_time, body_text |
| Unified view | `DOCS.V_ALL_DOCS` | 18 | All columns above, UNION ALL |

Temporal range: 2026-06-05 to 2026-09-16. Covers all four episodes (HIST_2026_06, HIST_2026_07, CHALLENGE_2026_08, GOLDEN_2026_09).

## Evidence pipeline

```
Document corpus (18 docs)
    ↓
Entity + Temporal Matching
  (entity_ref ↔ edge supplier/warehouse/order/customer,
   doc within -14 to +7 days of edge window)
    ↓
40 document-edge candidate pairs across 28/29 chain edges
    ↓
AI Classification (Cortex AI_COMPLETE, llama3.1-70b)
  → SUPPORTS | CONTRADICTS | CONTEXT | IRRELEVANT
    ↓
Rule-based Contradiction Override
  (docs stating "on schedule"/"no delays" matched to disruption edges)
    ↓
Evidence Scoring
  entity_match (35%) + temporal_match (25%) + semantic_class (40%)
    ↓
ANALYTICS.PROPAGATION_EVIDENCE (40 rows)
    ↓
Edge-level Aggregation → ANALYTICS.PROPAGATION_EVIDENCE_SUMMARY (29 rows)
```

## Evidence results

### Golden chain (CHAIN_SC-G1): Supplier disruption → Revenue impact

| Step | Edge | Structural Score | Structural Class | Doc Evidence | Doc Status |
|------|------|-----------------|-----------------|-------------|------------|
| 1 | Schedule change → Shipment delay | 0.879 | CAUSAL_STATED | 1 support | SUPPORTED |
| 2 | Shipment delay → Warehouse backlog | 0.576 | HISTORICAL_SUPPORTED | 1 support | SUPPORTED |
| 3 | Warehouse backlog → Late delivery | 0.502 | HISTORICAL_SUPPORTED | 2 support | STRONGLY_SUPPORTED |
| 4 | Late delivery → Customer complaint | 0.670 | TEXT_SUPPORTED | 1 support | SUPPORTED |
| 5 | Complaint → Refund | 0.546 | TEXT_SUPPORTED | 1 support | SUPPORTED |
| 6 | Refund → Revenue impact | 0.570 | HISTORICAL_SUPPORTED | 1 support | SUPPORTED |

**100% document evidence coverage.** Every edge in the golden chain has supporting document evidence.

### Historical chains (CHAIN_SC-H1, CHAIN_SC-H2)

| Chain | Edges | With Evidence | Supported | Gaps |
|-------|-------|--------------|-----------|------|
| CHAIN_SC-H1 (June) | 6 | 4 | 4 | 2 (step 1: schedule→delay, step 6: refund→revenue) |
| CHAIN_SC-H2 (July) | 6 | 5 | 5 | 1 (step 6: refund→revenue) |

### Challenge chain (CHAIN_SC-C1)

| Chain | Edges | With Evidence | Supported |
|-------|-------|--------------|-----------|
| CHAIN_SC-C1 | 1 (partial) | 1 | 1 |

Only step 1 (schedule→delay) was retained by Phase 2. Steps 2, 3, 6 fell below the 0.40 threshold (cold-start). See cold-start analysis below.

### Distractor/minor chains

| Chain | Evidence Status | Notes |
|-------|----------------|-------|
| CHAIN_OR_OR-C4 | MIXED_EVIDENCE | Positive ticket ST-C3 contradicts late-delivery→complaint edge |
| CHAIN_OR_OR-D1 | MIXED_EVIDENCE | SC-D1 "on schedule" contradicts late-delivery→complaint edge |
| CHAIN_SH_SH-D1 | CONTRADICTED | SC-D1 "on schedule" directly contradicts delay→backlog |
| CHAIN_SH_SH-D2 | CONTRADICTED | SC-D1 "on schedule" directly contradicts delay→backlog |
| CHAIN_SH_SH-C3 | NO_DOCUMENT_EVIDENCE | No docs reference WH-EAST in August |

### Overall metrics

| Metric | Value |
|--------|-------|
| Total chain edges | 29 |
| Edges with document evidence | 24 (82.8%) |
| Edges without document evidence | 5 (17.2%) |
| Supported edges | 20 |
| Strongly supported edges | 4 |
| Mixed evidence edges | 2 |
| Contradicted edges | 2 |
| No document evidence | 5 |
| Total supporting doc matches | 26 |
| Total contradicting doc matches | 4 |
| Total context doc matches | 10 |
| Unique documents used | 13 of 18 (72.2%) |

## Supporting evidence

Representative snippets from the golden chain:

**Step 1 — Schedule change → Shipment delay** (SC-G1):
> "Notice: due to a port closure we are moving your delivery window for WH-WEST back by approximately 10 days. All inbound shipments this week are affected."

**Step 4 — Late delivery → Customer complaint** (ST-G4):
> "Late again. Promised date was days ago. Please refund the order."

**Step 5 — Complaint → Refund** (ST-G1):
> "My order is almost two weeks late and no one informed me. This is unacceptable, I want a refund."

**Challenge step 1 — Schedule change → Shipment delay** (SC-C1):
> "Critical update: a production line failure at our central facility will delay all outbound shipments to WH-CENTRAL by approximately one week."

## Contradictory evidence

Four contradictions detected across 3 edges:

**CHAIN_SH_SH-D1 / D2: Delay → Backlog (CONTRADICTED)**
Document SC-D1: *"Routine confirmation: your WH-EAST shipment is on schedule. No changes to the delivery window."*
The structured data suggests a shipment delay → warehouse backlog for WH-EAST, but the supplier explicitly confirms the shipment is on schedule. This edge relies solely on structural signals; the supplier communication directly contradicts it.

**CHAIN_OR_OR-C4: Late delivery → Complaint (MIXED_EVIDENCE)**
Document ST-C3: *"Excellent turnaround on our recent order. Impressed with the service quality this month."*
A positive customer ticket matched to the same temporal window contradicts the complaint narrative, though a separate ticket (ST-C4) does support it with "Order arrived a couple days late."

**CHAIN_OR_OR-D1: Late delivery → Complaint (MIXED_EVIDENCE)**
Document SC-D1: *"Routine confirmation: your WH-EAST shipment is on schedule."*
On-schedule confirmation from the supplier weakens the late-delivery hypothesis, though the customer ticket (ST-D1) confirms a delivery was late.

## Evidence gaps

5 edges have no document evidence:

| Chain | Edge | Structural Score | Reason |
|-------|------|-----------------|--------|
| CHAIN_SC-H1 step 1 | Schedule → Delay | 0.850 | SC-H1 matched to step 2 (delay→backlog) but not step 1 due to entity join path |
| CHAIN_SC-H1 step 6 | Refund → Revenue | 0.516 | No document discusses refund-to-revenue impact explicitly |
| CHAIN_SC-H2 step 6 | Refund → Revenue | 0.530 | Same gap: refund→revenue is a financial aggregation not captured in comms |
| CHAIN_RF_RF-C3 | Refund → Revenue | 0.403 | Isolated east-region refund; no related documents |
| CHAIN_SH_SH-C3 | Delay → Backlog | 0.454 | No documents reference WH-EAST shipments in early August |

The **refund → revenue impact** transition consistently lacks document evidence across all episodes. This is expected: revenue impact is an aggregated metric, not typically discussed in individual supplier communications or support tickets. This edge type relies on structural and historical evidence only.

## Cold-start impact

### Challenge episode edges that Phase 2 missed (FALSE_NEGATIVE)

| Step | Edge | Phase 2 Score | Phase 2 Textual | Phase 3 Doc Evidence | Strengthened? |
|------|------|--------------|----------------|---------------------|--------------|
| 2 | SH-C1 → WH-CENTRAL (delay→backlog) | 0.2812 | 0.0 | SC-C1 SUPPORTS (entity=1.0) | **Yes** |
| 3 | WH-CENTRAL → OR-C1 (backlog→late delivery) | 0.3726 | 0.0 | SC-C1 + ST-C1 both SUPPORT (entity=0.9, 1.0) | **Yes** |
| 6 | RF-C1 → central (refund→revenue) | 0.3251 | 0.0 | ST-C1, ST-C2 weakly support (entity=0.3) | **Marginal** |

### Analysis

**Edge 2 (delay → backlog):** SC-C1 states *"production line failure at our central facility will delay all outbound shipments to WH-CENTRAL by approximately one week."* This directly references WH-CENTRAL and confirms disruption to the warehouse supply pipeline. Phase 2 scored this edge at 0.2812 because textual=0 and historical=0 for the novel entity WH-CENTRAL. Document evidence provides strong support (entity_match=1.0) that Phase 2 could not access because the textual component in Phase 2 only examines the edge's own endpoint documents, not cross-referencing the supplier communication.

**Edge 3 (backlog → late delivery):** Two documents support: SC-C1 provides upstream context (warehouse delays), and ST-C1 says *"order was supposed to arrive last week but it is almost a week overdue."* The support ticket directly confirms the late delivery, establishing the connection between the warehouse disruption and order impact. Phase 2 scored 0.3726 with zero textual evidence.

**Edge 6 (refund → revenue):** Only indirect support exists. ST-C1 and ST-C2 mention refund requests, but no document explicitly discusses the revenue impact of those refunds. This is a structural gap: revenue impact is a financial aggregation concept that does not appear in operational communications.

**Conclusion:** Phase 3 semantic evidence provides a genuinely different evidence modality for 2 of 3 cold-start failures. The document evidence is strong enough that, if Phase 2 had access to it, edges 2 and 3 would likely have cleared the retention threshold. Edge 6 remains weakly supported because the refund→revenue relationship is inherently an analytical inference not typically documented in business communications.

## Validation

| Metric | Value |
|--------|-------|
| Document evidence coverage (chain edges) | 82.8% (24/29) |
| Supporting evidence precision (supports / all classified) | 65.0% (26/40) |
| Contradiction detection rate | 10.0% (4/40) |
| Irrelevant document rate | 0.0% (0/40) |
| Context document rate | 25.0% (10/40) |
| Golden chain coverage | 100% (6/6 edges) |
| Historical chain avg coverage | 75.0% |
| Challenge chain retained-edge coverage | 100% (1/1 retained edge) |
| Cold-start edges with document evidence | 2 of 3 strongly supported |
| Unique documents contributing evidence | 13 of 18 (72.2%) |

Ground truth for per-document classification accuracy is not available — the document corpus does not have labeled evidence classes. The metrics above are computed from the pipeline output and represent system behavior, not externally validated precision/recall.

## Architectural limitations

1. **Retrieval relies on explicit entity overlap.** Documents are matched to edges via shared supplier, warehouse, order, or customer identifiers plus temporal proximity. Documents that discuss a situation without naming specific entities (e.g., "logistics issues in the region") will not be matched unless an entity ID appears in metadata.

2. **Semantic ambiguity in AI classification.** The LLM classifies evidence conservatively — "on schedule" confirmations were classified as CONTEXT rather than CONTRADICTS without the rule-based override. Contradiction detection requires explicit heuristics for common patterns (positive sentiment vs. disruption edge, normalcy confirmation vs. delay edge).

3. **Cold-start limitation partially addressed, not eliminated.** Phase 3 provides document evidence for 2 of 3 cold-start failures, but cannot solve the fundamental problem: Phase 2 must retain an edge before Phase 3 can enrich it. The evidence exists but is unreachable until the Phase 2 retention threshold is met. A future architecture could feed document evidence back into scoring, but that would violate the Phase 3 constraint of not modifying Phase 2 weights.

4. **Refund → Revenue gap is structural.** Revenue impact is an aggregated metric. No individual document discusses "our refunds caused a revenue decline." This transition will consistently rely on structural and historical evidence only.

5. **Configured transition graph limitation persists.** Phase 3 can only enrich edges that the Phase 2 transition graph permits. Novel propagation paths not in LAG_WINDOWS cannot be discovered by either Phase 2 or Phase 3.

6. **Document corpus is small (18 docs).** With a production-scale corpus, retrieval precision would need additional filtering (e.g., relevance thresholds, top-k limits) to avoid noise. The current entity-match approach works well at this scale but may not scale linearly.

## Recommendation

Phase 3 is **ready for Phase 4**. The evidence layer:

- Covers 82.8% of chain edges with document evidence
- Detects contradictions (4 instances across 3 edges)
- Identifies evidence gaps explicitly (5 edges, 3 structurally explained)
- Demonstrates that semantic evidence provides a genuinely different modality from Phase 2 structural scoring (2/3 cold-start failures have strong document support)
- Produces explainable, edge-level evidence summaries suitable for an investigation interface
- Does not modify Phase 2 objects or scoring

The Phase 4 agent should use `PROPAGATION_EVIDENCE_SUMMARY` for chain-level evidence narratives and `PROPAGATION_EVIDENCE` for drill-down into specific documents. Cortex Search (`DOC_SEARCH`) is available for free-text investigative queries.
