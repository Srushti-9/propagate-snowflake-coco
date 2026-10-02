-- PROPAGATE :: Phase 3 :: 13_phase3_evidence_layer.sql
-- AI Evidence Layer: connects inferred propagation relationships to unstructured
-- business documents. Enriches the existing propagation graph with document-backed
-- evidence without modifying Phase 2 scoring weights or thresholds.
--
-- Pipeline: Document → Entity/Temporal Matching → AI Classification → Evidence Scoring → Summary
--
-- Uses Cortex Search (PROPAGATE.DOCS.DOC_SEARCH) for availability confirmation and
-- Cortex AI_COMPLETE (llama3.1-70b) for evidence classification.
--
-- Creates:
--   ANALYTICS.PROPAGATION_EVIDENCE         (per-document, per-edge evidence records)
--   ANALYTICS.PROPAGATION_EVIDENCE_SUMMARY (per-edge aggregated evidence status)
--   ANALYTICS.COLD_START_EVIDENCE          (Phase 2 cold-start gap analysis)
--
-- Does NOT modify: SCORED_EDGES, CHAIN_EDGES, CHAINS, LAG_WINDOWS, or any Phase 2 object.

--------------------------------------------------------------------------------
-- Step 1: Match documents to chain edges via entity overlap + temporal window
--------------------------------------------------------------------------------

CREATE OR REPLACE TEMPORARY TABLE PROPAGATE.ANALYTICS._DOC_EDGE_CANDIDATES AS
WITH chain_edge_entities AS (
    SELECT
        ce.CHAIN_ID,
        ce.STEP_NO,
        ce.EDGE_ID,
        ce.FROM_EVENT,
        ce.TO_EVENT,
        ce.RELATION,
        ce.EVIDENCE_SCORE  AS structural_evidence_score,
        ce.EVIDENCE_CLASS  AS structural_evidence_class,
        ef.EVENT_TIME      AS from_time,
        et.EVENT_TIME      AS to_time,
        ef.EVENT_TYPE      AS from_type,
        et.EVENT_TYPE      AS to_type,
        COALESCE(ef.LINK_SUPPLIER_ID, et.LINK_SUPPLIER_ID)   AS edge_supplier,
        COALESCE(ef.LINK_WAREHOUSE_ID, et.LINK_WAREHOUSE_ID) AS edge_warehouse,
        COALESCE(ef.LINK_CUSTOMER_ID,  et.LINK_CUSTOMER_ID)  AS edge_customer,
        COALESCE(ef.LINK_ORDER_ID,     et.LINK_ORDER_ID)     AS edge_order,
        COALESCE(ef.LINK_SHIPMENT_ID,  et.LINK_SHIPMENT_ID)  AS edge_shipment,
        COALESCE(ef.LINK_REGION,       et.LINK_REGION)       AS edge_region
    FROM PROPAGATE.ANALYTICS.CHAIN_EDGES ce
    JOIN PROPAGATE.ANALYTICS.EVENT_LOG ef ON ef.EVENT_ID = ce.FROM_EVENT
    JOIN PROPAGATE.ANALYTICS.EVENT_LOG et ON et.EVENT_ID = ce.TO_EVENT
)
SELECT
    e.CHAIN_ID,
    e.STEP_NO,
    e.EDGE_ID,
    e.FROM_EVENT,
    e.TO_EVENT,
    e.RELATION,
    e.structural_evidence_score,
    e.structural_evidence_class,
    e.from_type,
    e.to_type,
    e.from_time,
    e.to_time,
    e.edge_supplier,
    e.edge_warehouse,
    e.edge_order,
    e.edge_region,
    d.DOC_ID,
    d.DOC_TYPE,
    d.ENTITY_REF  AS doc_entity,
    d.ORDER_REF   AS doc_order,
    d.WAREHOUSE_REF AS doc_warehouse,
    d.EVENT_TIME  AS doc_time,
    d.BODY_TEXT,
    -- entity match scoring: direct entity overlap scores highest
    CASE
        WHEN d.ENTITY_REF = e.edge_supplier   THEN 1.0
        WHEN d.ORDER_REF  = e.edge_order       THEN 1.0
        WHEN d.WAREHOUSE_REF = e.edge_warehouse THEN 0.9
        WHEN d.DOC_TYPE = 'SUPPORT_TICKET' AND d.ENTITY_REF = e.edge_customer THEN 0.8
        ELSE 0.0
    END AS entity_match_score,
    -- temporal match scoring: linear decay from 1.0 at 0 hours to 0.0 at 504 hours (21 days)
    GREATEST(0, 1.0 - (
        LEAST(
            ABS(DATEDIFF('hour', d.EVENT_TIME, e.from_time)),
            ABS(DATEDIFF('hour', d.EVENT_TIME, e.to_time))
        ) / (21.0 * 24)
    )) AS temporal_match_score
FROM chain_edge_entities e
CROSS JOIN PROPAGATE.DOCS.V_ALL_DOCS d
WHERE
    -- require at least one entity overlap
    (
        d.ENTITY_REF   = e.edge_supplier
        OR d.ORDER_REF  = e.edge_order
        OR d.WAREHOUSE_REF = e.edge_warehouse
        OR d.ENTITY_REF = e.edge_customer
    )
    -- temporal window: 14 days before source to 7 days after target
    AND d.EVENT_TIME BETWEEN DATEADD('day', -14, e.from_time)
                         AND DATEADD('day',   7, e.to_time);

--------------------------------------------------------------------------------
-- Step 2: AI evidence classification via Cortex COMPLETE
--------------------------------------------------------------------------------

CREATE OR REPLACE TEMPORARY TABLE PROPAGATE.ANALYTICS._DOC_EVIDENCE_RAW AS
SELECT
    c.*,
    TRIM(SNOWFLAKE.CORTEX.COMPLETE(
        'llama3.1-70b',
        CONCAT(
            'You are classifying whether a business document supports, contradicts, ',
            'or is merely contextual for a proposed propagation relationship in a supply chain.\n\n',
            'PROPOSED RELATIONSHIP: ', c.RELATION, '\n',
            'Source event type: ', c.from_type, '\n',
            'Target event type: ', c.to_type, '\n',
            'Time window: ', TO_VARCHAR(c.from_time, 'YYYY-MM-DD'),
            ' to ', TO_VARCHAR(c.to_time, 'YYYY-MM-DD'), '\n',
            'Shared entities: ',
              COALESCE('supplier=' || c.edge_supplier || ' ', ''),
              COALESCE('warehouse=' || c.edge_warehouse || ' ', ''),
              COALESCE('order=' || c.edge_order || ' ', ''),
              COALESCE('region=' || c.edge_region, ''),
            '\n\nDOCUMENT (', c.DOC_TYPE, ' from ', TO_VARCHAR(c.doc_time, 'YYYY-MM-DD'), '):\n',
            LEFT(c.BODY_TEXT, 500), '\n\n',
            'Classify as exactly one of:\n',
            'SUPPORTS - evidence consistent with this propagation relationship\n',
            'CONTRADICTS - evidence that weakens or contradicts this relationship\n',
            'CONTEXT - relevant but does not establish support or contradiction\n',
            'IRRELEVANT - does not meaningfully relate to this relationship\n\n',
            'Reply: CLASSIFICATION|one-sentence explanation'
        )
    )) AS ai_response
FROM PROPAGATE.ANALYTICS._DOC_EDGE_CANDIDATES c;

--------------------------------------------------------------------------------
-- Step 3: Build PROPAGATION_EVIDENCE with contradiction detection
--------------------------------------------------------------------------------

CREATE OR REPLACE TABLE PROPAGATE.ANALYTICS.PROPAGATION_EVIDENCE AS
WITH parsed AS (
    SELECT
        r.*,
        UPPER(TRIM(SPLIT_PART(r.ai_response, '|', 1))) AS raw_evidence_class,
        TRIM(SPLIT_PART(r.ai_response, '|', 2)) AS ai_explanation,
        -- rule-based contradiction: doc states normalcy but edge proposes disruption
        CASE
            WHEN (LOWER(r.BODY_TEXT) LIKE '%on schedule%'
                  OR LOWER(r.BODY_TEXT) LIKE '%proceeding normally%'
                  OR LOWER(r.BODY_TEXT) LIKE '%no delays%'
                  OR LOWER(r.BODY_TEXT) LIKE '%no changes%')
                 AND r.RELATION IN ('SCHEDULE_CHANGE_PRECEDES_DELAY',
                      'DELAY_PRECEDES_BACKLOG','BACKLOG_PRECEDES_LATE_DELIVERY',
                      'LATE_DELIVERY_PRECEDES_COMPLAINT')
            THEN TRUE
            WHEN (LOWER(r.BODY_TEXT) LIKE '%excellent%'
                  OR LOWER(r.BODY_TEXT) LIKE '%impressed%'
                  OR LOWER(r.BODY_TEXT) LIKE '%great service%'
                  OR LOWER(r.BODY_TEXT) LIKE '%very satisfied%'
                  OR LOWER(r.BODY_TEXT) LIKE '%fast delivery%')
                 AND r.RELATION IN ('LATE_DELIVERY_PRECEDES_COMPLAINT',
                      'COMPLAINT_ASSOCIATED_WITH_REFUND')
            THEN TRUE
            ELSE FALSE
        END AS contradiction_detected
    FROM PROPAGATE.ANALYTICS._DOC_EVIDENCE_RAW r
),
classified AS (
    SELECT p.*,
        CASE
            WHEN p.contradiction_detected THEN 'CONTRADICTS'
            WHEN p.raw_evidence_class IN ('SUPPORTS','CONTRADICTS','CONTEXT','IRRELEVANT')
                 THEN p.raw_evidence_class
            ELSE 'CONTEXT'
        END AS evidence_class
    FROM parsed p
)
SELECT
    ROW_NUMBER() OVER (ORDER BY c.CHAIN_ID, c.STEP_NO, c.DOC_ID) AS evidence_id,
    c.FROM_EVENT    AS source_event_id,
    c.TO_EVENT      AS target_event_id,
    c.EDGE_ID,
    c.CHAIN_ID,
    c.STEP_NO,
    c.RELATION,
    c.structural_evidence_score,
    c.structural_evidence_class,
    c.DOC_ID        AS document_id,
    c.DOC_TYPE      AS document_type,
    c.doc_time      AS document_timestamp,
    c.evidence_class,
    c.entity_match_score,
    c.temporal_match_score,
    CASE c.evidence_class
        WHEN 'SUPPORTS'    THEN 1.0
        WHEN 'CONTRADICTS' THEN 0.8   -- relevant but negative
        WHEN 'CONTEXT'     THEN 0.4
        ELSE 0.0
    END AS semantic_match_score,
    -- composite relevance: entity 35%, temporal 25%, semantic 40%
    ROUND(
        (c.entity_match_score * 0.35) +
        (c.temporal_match_score * 0.25) +
        (CASE c.evidence_class
            WHEN 'SUPPORTS'    THEN 1.0
            WHEN 'CONTRADICTS' THEN 0.8
            WHEN 'CONTEXT'     THEN 0.4
            ELSE 0.0
        END * 0.40),
    4) AS relevance_score,
    CASE
        WHEN c.evidence_class = 'SUPPORTS' AND c.entity_match_score >= 0.9
             AND c.temporal_match_score >= 0.8 THEN 'STRONG'
        WHEN c.evidence_class = 'SUPPORTS' AND (c.entity_match_score >= 0.8
             OR c.temporal_match_score >= 0.7) THEN 'MODERATE'
        WHEN c.evidence_class = 'SUPPORTS' THEN 'WEAK'
        WHEN c.evidence_class = 'CONTRADICTS' AND c.entity_match_score >= 0.9
             THEN 'STRONG_CONTRADICTION'
        WHEN c.evidence_class = 'CONTRADICTS' THEN 'WEAK_CONTRADICTION'
        WHEN c.evidence_class = 'CONTEXT' THEN 'CONTEXTUAL'
        ELSE 'NONE'
    END AS evidence_strength,
    c.ai_explanation AS evidence_summary,
    LEFT(c.BODY_TEXT, 200) AS evidence_snippet,
    CASE
        WHEN c.contradiction_detected THEN 'RULE_BASED_CONTRADICTION'
        ELSE 'AI_CLASSIFICATION'
    END AS extraction_method
FROM classified c
ORDER BY c.CHAIN_ID, c.STEP_NO, c.DOC_ID;

--------------------------------------------------------------------------------
-- Step 4: PROPAGATION_EVIDENCE_SUMMARY (per-edge aggregation)
--------------------------------------------------------------------------------
-- Evidence statuses:
--   STRONGLY_SUPPORTED  : >=2 supporting docs with max relevance >= 0.80
--   SUPPORTED           : >=1 supporting doc with max relevance >= 0.70
--   WEAK_EVIDENCE       : >=1 supporting doc below 0.70
--   MIXED_EVIDENCE      : both supporting and contradicting docs present
--   CONTRADICTED        : contradicting docs only, no supporting docs
--   NO_DOCUMENT_EVIDENCE: no documents matched this edge
--
-- Document evidence score formula (when meaningful docs exist):
--   (supporting_count * avg_support_relevance - contradicting_count * max_contradict_relevance)
--   / (supporting_count + contradicting_count)
-- Range: [-1, +1]. Positive = net support. Negative = net contradiction.

CREATE OR REPLACE TABLE PROPAGATE.ANALYTICS.PROPAGATION_EVIDENCE_SUMMARY AS
WITH edge_agg AS (
    SELECT
        EDGE_ID, CHAIN_ID, STEP_NO, RELATION,
        source_event_id, target_event_id,
        structural_evidence_score, structural_evidence_class,
        COUNT(*) AS total_documents,
        COUNT(CASE WHEN evidence_class = 'SUPPORTS' THEN 1 END)    AS supporting_count,
        COUNT(CASE WHEN evidence_class = 'CONTRADICTS' THEN 1 END) AS contradicting_count,
        COUNT(CASE WHEN evidence_class = 'CONTEXT' THEN 1 END)     AS context_count,
        COUNT(CASE WHEN evidence_class = 'IRRELEVANT' THEN 1 END)  AS irrelevant_count,
        MAX(CASE WHEN evidence_class = 'SUPPORTS' THEN relevance_score END)    AS max_support_score,
        MAX(CASE WHEN evidence_class = 'CONTRADICTS' THEN relevance_score END) AS max_contradict_score,
        AVG(CASE WHEN evidence_class = 'SUPPORTS' THEN relevance_score END)    AS avg_support_score,
        MAX(CASE WHEN evidence_class = 'SUPPORTS' THEN evidence_summary END)    AS strongest_support,
        MAX(CASE WHEN evidence_class = 'SUPPORTS' THEN evidence_snippet END)    AS strongest_support_snippet,
        MAX(CASE WHEN evidence_class = 'SUPPORTS' THEN document_id END)         AS strongest_support_doc,
        MAX(CASE WHEN evidence_class = 'CONTRADICTS' THEN evidence_summary END)    AS strongest_contradiction,
        MAX(CASE WHEN evidence_class = 'CONTRADICTS' THEN evidence_snippet END)    AS strongest_contradiction_snippet,
        MAX(CASE WHEN evidence_class = 'CONTRADICTS' THEN document_id END)         AS strongest_contradiction_doc,
        ARRAY_AGG(DISTINCT document_id)  AS evidence_document_ids,
        MIN(document_timestamp) AS evidence_timestamp_min,
        MAX(document_timestamp) AS evidence_timestamp_max
    FROM PROPAGATE.ANALYTICS.PROPAGATION_EVIDENCE
    GROUP BY 1,2,3,4,5,6,7,8
),
all_edges AS (
    SELECT ce.EDGE_ID, ce.CHAIN_ID, ce.STEP_NO, ce.RELATION,
           ce.FROM_EVENT AS source_event_id, ce.TO_EVENT AS target_event_id,
           ce.EVIDENCE_SCORE AS structural_evidence_score,
           ce.EVIDENCE_CLASS AS structural_evidence_class
    FROM PROPAGATE.ANALYTICS.CHAIN_EDGES ce
)
SELECT
    ae.EDGE_ID, ae.CHAIN_ID, ae.STEP_NO, ae.RELATION,
    ae.source_event_id, ae.target_event_id,
    ae.structural_evidence_score, ae.structural_evidence_class,
    COALESCE(ea.total_documents, 0)      AS total_documents,
    COALESCE(ea.supporting_count, 0)     AS supporting_count,
    COALESCE(ea.contradicting_count, 0)  AS contradicting_count,
    COALESCE(ea.context_count, 0)        AS context_count,
    COALESCE(ea.irrelevant_count, 0)     AS irrelevant_count,
    ea.max_support_score,
    ea.max_contradict_score,
    CASE
        WHEN COALESCE(ea.supporting_count, 0) + COALESCE(ea.contradicting_count, 0) = 0 THEN NULL
        ELSE ROUND(
            (COALESCE(ea.supporting_count, 0) * COALESCE(ea.avg_support_score, 0)
             - COALESCE(ea.contradicting_count, 0) * COALESCE(ea.max_contradict_score, 0))
            / (COALESCE(ea.supporting_count, 0) + COALESCE(ea.contradicting_count, 0)),
        4)
    END AS document_evidence_score,
    CASE
        WHEN COALESCE(ea.total_documents, 0) = 0 THEN 'NO_DOCUMENT_EVIDENCE'
        WHEN ea.contradicting_count > 0 AND COALESCE(ea.supporting_count, 0) = 0
            THEN 'CONTRADICTED'
        WHEN ea.contradicting_count > 0 AND ea.supporting_count > 0
            THEN 'MIXED_EVIDENCE'
        WHEN ea.supporting_count >= 2 AND ea.max_support_score >= 0.8
            THEN 'STRONGLY_SUPPORTED'
        WHEN ea.supporting_count >= 1 AND ea.max_support_score >= 0.7
            THEN 'SUPPORTED'
        WHEN ea.supporting_count >= 1
            THEN 'WEAK_EVIDENCE'
        ELSE 'NO_DOCUMENT_EVIDENCE'
    END AS evidence_status,
    ea.strongest_support,
    ea.strongest_support_snippet,
    ea.strongest_support_doc,
    ea.strongest_contradiction,
    ea.strongest_contradiction_snippet,
    ea.strongest_contradiction_doc,
    ea.evidence_document_ids,
    ea.evidence_timestamp_min,
    ea.evidence_timestamp_max
FROM all_edges ae
LEFT JOIN edge_agg ea ON ea.EDGE_ID = ae.EDGE_ID AND ea.CHAIN_ID = ae.CHAIN_ID
ORDER BY ae.CHAIN_ID, ae.STEP_NO;

--------------------------------------------------------------------------------
-- Step 5: Cold-start evidence analysis
-- Tests whether semantic evidence improves coverage for Phase 2 false negatives
--------------------------------------------------------------------------------

CREATE OR REPLACE TABLE PROPAGATE.ANALYTICS.COLD_START_EVIDENCE AS
WITH failed_edges AS (
    SELECT 2 AS step, 'DELAY_PRECEDES_BACKLOG' AS relation,
           'SH-C1' AS from_id, 'WH-CENTRAL' AS to_id,
           'SHIPMENT_DELAY' AS from_type, 'WAREHOUSE_BACKLOG' AS to_type,
           0.2812 AS phase2_score, 'FALSE_NEGATIVE' AS phase2_result
    UNION ALL
    SELECT 3, 'BACKLOG_PRECEDES_LATE_DELIVERY',
           'WH-CENTRAL', 'OR-C1', 'WAREHOUSE_BACKLOG', 'ORDER_DELIVERY',
           0.3726, 'FALSE_NEGATIVE'
    UNION ALL
    SELECT 6, 'REFUNDS_ASSOCIATED_WITH_REVENUE_IMPACT',
           'RF-C1', 'central', 'REFUND', 'REVENUE',
           0.3251, 'FALSE_NEGATIVE'
),
candidate_docs AS (
    -- Edge 2: delay -> backlog for WH-CENTRAL (SC-C1 mentions WH-CENTRAL delays)
    SELECT fe.*, d.DOC_ID, d.DOC_TYPE, d.BODY_TEXT, d.EVENT_TIME AS doc_time,
           d.ENTITY_REF, d.WAREHOUSE_REF, d.ORDER_REF, 1.0 AS entity_match
    FROM failed_edges fe
    CROSS JOIN PROPAGATE.DOCS.V_ALL_DOCS d
    WHERE fe.step = 2 AND d.DOC_ID = 'SC-C1'
    UNION ALL
    -- Edge 3: backlog -> late delivery (SC-C1 warehouse match, ST-C1 order match)
    SELECT fe.*, d.DOC_ID, d.DOC_TYPE, d.BODY_TEXT, d.EVENT_TIME,
           d.ENTITY_REF, d.WAREHOUSE_REF, d.ORDER_REF,
           CASE WHEN d.ORDER_REF = 'OR-C1' THEN 1.0 WHEN d.WAREHOUSE_REF = 'WH-CENTRAL' THEN 0.9 ELSE 0.4 END
    FROM failed_edges fe
    CROSS JOIN PROPAGATE.DOCS.V_ALL_DOCS d
    WHERE fe.step = 3 AND d.DOC_ID IN ('SC-C1', 'ST-C1')
    UNION ALL
    -- Edge 6: refund -> revenue (only indirect semantic support)
    SELECT fe.*, d.DOC_ID, d.DOC_TYPE, d.BODY_TEXT, d.EVENT_TIME,
           d.ENTITY_REF, d.WAREHOUSE_REF, d.ORDER_REF, 0.3
    FROM failed_edges fe
    CROSS JOIN PROPAGATE.DOCS.V_ALL_DOCS d
    WHERE fe.step = 6 AND d.DOC_ID IN ('ST-C1', 'ST-C2')
)
SELECT
    cd.step,
    cd.relation,
    cd.from_id || ' -> ' || cd.to_id AS edge,
    cd.phase2_score,
    cd.phase2_result,
    cd.DOC_ID,
    cd.DOC_TYPE,
    cd.entity_match,
    LEFT(cd.BODY_TEXT, 200) AS snippet,
    TRIM(SNOWFLAKE.CORTEX.COMPLETE(
        'llama3.1-70b',
        CONCAT(
            'Classify if this document supports the proposed supply-chain propagation.\n\n',
            'RELATIONSHIP: ', cd.relation, ' (', cd.from_type, ' -> ', cd.to_type, ')\n',
            'From: ', cd.from_id, ' To: ', cd.to_id, '\n\n',
            'DOCUMENT (', cd.DOC_TYPE, '):\n', LEFT(cd.BODY_TEXT, 400), '\n\n',
            'Reply: SUPPORTS|CONTRADICTS|CONTEXT|IRRELEVANT followed by | and one sentence.'
        )
    )) AS ai_classification,
    CASE
        WHEN cd.entity_match >= 0.9
            THEN 'Document evidence could strengthen this edge if Phase 2 had retained it'
        WHEN cd.entity_match >= 0.5
            THEN 'Document provides partial semantic support for this relationship'
        ELSE 'Document has only indirect relevance to this relationship'
    END AS cold_start_assessment
FROM candidate_docs cd
ORDER BY cd.step, cd.DOC_ID;
