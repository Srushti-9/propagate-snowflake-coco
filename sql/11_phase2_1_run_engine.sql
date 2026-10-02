-- PROPAGATE :: Phase 2.1 :: 11_phase2_1_run_engine.sql
-- Re-runs the UNCHANGED Phase 2 engine on the expanded dataset (original + challenge).
-- Every SQL statement below is copied verbatim from 04-07. NO engine logic is modified.
-- DOC_SIGNALS is rebuilt via Cortex AI functions (same approach as Phase 4).

-- ===================================================================
-- STEP A: Rebuild EVENT_LOG (from 04_event_spine.sql — verbatim)
-- ===================================================================
CREATE OR REPLACE TABLE PROPAGATE.ANALYTICS.EVENT_LOG (
  event_id STRING PRIMARY KEY, event_time TIMESTAMP_NTZ, event_type STRING, business_function STRING,
  entity_type STRING, entity_id STRING, magnitude FLOAT, deviation_score FLOAT,
  link_supplier_id STRING, link_warehouse_id STRING, link_customer_id STRING, link_order_id STRING,
  link_shipment_id STRING, link_region STRING, source_table STRING, source_ref STRING, text_ref STRING
);

INSERT INTO PROPAGATE.ANALYTICS.EVENT_LOG
SELECT 'EVT_SC_'||sc.doc_id, sc.event_time, 'SCHEDULE_CHANGE','SUPPLIER','SUPPLIER', sc.entity_ref,
       NULL, NULL, sc.entity_ref, sc.warehouse_ref, NULL, NULL, NULL, w.region,
       'DOCS.SUPPLIER_COMMS', sc.doc_id, sc.doc_id
FROM PROPAGATE.DOCS.SUPPLIER_COMMS sc
LEFT JOIN PROPAGATE.CORE.WAREHOUSES w ON w.warehouse_id = sc.warehouse_ref;

INSERT INTO PROPAGATE.ANALYTICS.EVENT_LOG
SELECT 'EVT_SH_'||s.shipment_id, s.planned_date::timestamp_ntz, 'SHIPMENT_DELAY','SHIPPING','SHIPMENT', s.shipment_id,
       s.delay_days,
       (s.delay_days - AVG(s.delay_days) OVER ()) / NULLIF(STDDEV_POP(s.delay_days) OVER (),0),
       s.supplier_id, s.dest_wh, NULL, NULL, s.shipment_id, w.region,
       'CORE.SHIPMENTS', s.shipment_id, NULL
FROM PROPAGATE.CORE.SHIPMENTS s
LEFT JOIN PROPAGATE.CORE.WAREHOUSES w ON w.warehouse_id = s.dest_wh;

INSERT INTO PROPAGATE.ANALYTICS.EVENT_LOG
SELECT 'EVT_WH_'||d.warehouse_id||'_'||TO_VARCHAR(d.date,'YYYYMMDD'), d.date::timestamp_ntz,
       'WAREHOUSE_BACKLOG','WAREHOUSE','WAREHOUSE', d.warehouse_id,
       d.backlog_units,
       (d.backlog_units - AVG(d.backlog_units) OVER (PARTITION BY d.warehouse_id))
         / NULLIF(STDDEV_POP(d.backlog_units) OVER (PARTITION BY d.warehouse_id),0),
       NULL, d.warehouse_id, NULL, NULL, NULL, w.region,
       'CORE.WAREHOUSE_DAILY', d.warehouse_id||'|'||TO_VARCHAR(d.date,'YYYY-MM-DD'), NULL
FROM PROPAGATE.CORE.WAREHOUSE_DAILY d
LEFT JOIN PROPAGATE.CORE.WAREHOUSES w ON w.warehouse_id = d.warehouse_id;

INSERT INTO PROPAGATE.ANALYTICS.EVENT_LOG
SELECT 'EVT_OR_'||o.order_id, o.delivered_date::timestamp_ntz, 'ORDER_DELIVERY','FULFILLMENT','ORDER', o.order_id,
       DATEDIFF('day', o.promised_date, o.delivered_date) AS lateness,
       (DATEDIFF('day', o.promised_date, o.delivered_date)
          - AVG(DATEDIFF('day', o.promised_date, o.delivered_date)) OVER ())
         / NULLIF(STDDEV_POP(DATEDIFF('day', o.promised_date, o.delivered_date)) OVER (),0),
       s.supplier_id, o.warehouse_id, o.customer_id, o.order_id, o.shipment_id, c.region,
       'CORE.ORDERS', o.order_id, NULL
FROM PROPAGATE.CORE.ORDERS o
LEFT JOIN PROPAGATE.CORE.CUSTOMERS c ON c.customer_id = o.customer_id
LEFT JOIN PROPAGATE.CORE.SHIPMENTS s ON s.shipment_id = o.shipment_id;

INSERT INTO PROPAGATE.ANALYTICS.EVENT_LOG
SELECT 'EVT_ST_'||t.doc_id, t.event_time, 'SUPPORT_TICKET','SUPPORT','SUPPORT_TICKET', t.doc_id,
       NULL, NULL,
       s.supplier_id, o.warehouse_id, t.entity_ref, t.order_ref, o.shipment_id, c.region,
       'DOCS.SUPPORT_TICKETS', t.doc_id, t.doc_id
FROM PROPAGATE.DOCS.SUPPORT_TICKETS t
LEFT JOIN PROPAGATE.CORE.ORDERS o ON o.order_id = t.order_ref
LEFT JOIN PROPAGATE.CORE.CUSTOMERS c ON c.customer_id = t.entity_ref
LEFT JOIN PROPAGATE.CORE.SHIPMENTS s ON s.shipment_id = o.shipment_id;

INSERT INTO PROPAGATE.ANALYTICS.EVENT_LOG
SELECT 'EVT_RF_'||r.refund_id, r.refund_date::timestamp_ntz, 'REFUND','FINANCE','REFUND', r.refund_id,
       r.amount,
       (r.amount - AVG(r.amount) OVER ()) / NULLIF(STDDEV_POP(r.amount) OVER (),0),
       s.supplier_id, o.warehouse_id, o.customer_id, r.order_id, o.shipment_id, c.region,
       'CORE.REFUNDS', r.refund_id, NULL
FROM PROPAGATE.CORE.REFUNDS r
LEFT JOIN PROPAGATE.CORE.ORDERS o ON o.order_id = r.order_id
LEFT JOIN PROPAGATE.CORE.CUSTOMERS c ON c.customer_id = o.customer_id
LEFT JOIN PROPAGATE.CORE.SHIPMENTS s ON s.shipment_id = o.shipment_id;

INSERT INTO PROPAGATE.ANALYTICS.EVENT_LOG
SELECT 'EVT_BM_'||b.region||'_'||TO_VARCHAR(b.metric_date,'YYYYMMDD'), b.metric_date::timestamp_ntz,
       'REVENUE','FINANCE','BUSINESS_METRIC', b.region,
       b.revenue,
       (b.revenue - AVG(b.revenue) OVER (PARTITION BY b.region))
         / NULLIF(STDDEV_POP(b.revenue) OVER (PARTITION BY b.region),0),
       NULL, NULL, NULL, NULL, NULL, b.region,
       'CORE.BUSINESS_METRICS', b.region||'|'||TO_VARCHAR(b.metric_date,'YYYY-MM-DD'), NULL
FROM PROPAGATE.CORE.BUSINESS_METRICS b;

-- ===================================================================
-- STEP B: Rebuild DOC_SIGNALS (AI enrichment — same approach as Phase 4)
-- ===================================================================
CREATE OR REPLACE TABLE PROPAGATE.ANALYTICS.DOC_SIGNALS AS
WITH all_docs AS (
  SELECT doc_id, doc_type, body_text FROM PROPAGATE.DOCS.SUPPLIER_COMMS
  UNION ALL
  SELECT doc_id, doc_type, body_text FROM PROPAGATE.DOCS.SUPPORT_TICKETS
),
classified AS (
  SELECT doc_id, doc_type, body_text,
    SNOWFLAKE.CORTEX.SENTIMENT(body_text) AS sentiment,
    CASE doc_type
      WHEN 'SUPPLIER_COMM' THEN
        AI_CLASSIFY(body_text, ['SCHEDULE_CHANGE_DISRUPTION', 'ROUTINE_NOTICE', 'OTHER'])
      WHEN 'SUPPORT_TICKET' THEN
        AI_CLASSIFY(body_text, ['LATE_DELIVERY_COMPLAINT', 'DAMAGE_COMPLAINT', 'PRAISE', 'OTHER'])
    END AS classify_result
  FROM all_docs
)
SELECT doc_id, doc_type, sentiment,
  classify_result:"labels"[0]::string AS label,
  (doc_type = 'SUPPLIER_COMM' AND classify_result:"labels"[0]::string = 'SCHEDULE_CHANGE_DISRUPTION') AS asserts_cause
FROM classified;

-- ===================================================================
-- STEP C: Rebuild CANDIDATE_EDGES (from 05_candidate_linker.sql — verbatim)
-- ===================================================================
-- LAG_WINDOWS is unchanged (not recreated)

CREATE OR REPLACE TABLE PROPAGATE.ANALYTICS.CANDIDATE_EDGES (
  edge_id STRING, from_event STRING, to_event STRING,
  from_type STRING, to_type STRING, from_function STRING, to_function STRING,
  relation STRING, lag_days FLOAT, lag_hours FLOAT,
  shared_entity_type STRING, shared_entity_id STRING
);

INSERT INTO PROPAGATE.ANALYTICS.CANDIDATE_EDGES
SELECT a.event_id||'->'||b.event_id, a.event_id, b.event_id, a.event_type, b.event_type,
       a.business_function, b.business_function, 'SCHEDULE_CHANGE_PRECEDES_DELAY',
       DATEDIFF('day',a.event_time,b.event_time), DATEDIFF('hour',a.event_time,b.event_time),
       'SUPPLIER', a.link_supplier_id
FROM PROPAGATE.ANALYTICS.EVENT_LOG a
JOIN PROPAGATE.ANALYTICS.EVENT_LOG b
  ON a.event_type='SCHEDULE_CHANGE' AND b.event_type='SHIPMENT_DELAY'
 AND a.link_supplier_id = b.link_supplier_id
 AND (a.link_warehouse_id = b.link_warehouse_id OR a.link_warehouse_id IS NULL)
 AND b.event_time > a.event_time
 AND DATEDIFF('day',a.event_time,b.event_time) <= 14;

INSERT INTO PROPAGATE.ANALYTICS.CANDIDATE_EDGES
SELECT a.event_id||'->'||b.event_id, a.event_id, b.event_id, a.event_type, b.event_type,
       a.business_function, b.business_function, 'DELAY_PRECEDES_BACKLOG',
       DATEDIFF('day',a.event_time,b.event_time), DATEDIFF('hour',a.event_time,b.event_time),
       'WAREHOUSE', a.link_warehouse_id
FROM PROPAGATE.ANALYTICS.EVENT_LOG a
JOIN PROPAGATE.ANALYTICS.EVENT_LOG b
  ON a.event_type='SHIPMENT_DELAY' AND b.event_type='WAREHOUSE_BACKLOG'
 AND a.link_warehouse_id = b.link_warehouse_id
 AND b.event_time > a.event_time
 AND DATEDIFF('day',a.event_time,b.event_time) <= 10
 AND b.deviation_score >= 1.0;

INSERT INTO PROPAGATE.ANALYTICS.CANDIDATE_EDGES
SELECT a.event_id||'->'||b.event_id, a.event_id, b.event_id, a.event_type, b.event_type,
       a.business_function, b.business_function, 'BACKLOG_PRECEDES_LATE_DELIVERY',
       DATEDIFF('day',a.event_time,b.event_time), DATEDIFF('hour',a.event_time,b.event_time),
       'WAREHOUSE', a.link_warehouse_id
FROM PROPAGATE.ANALYTICS.EVENT_LOG a
JOIN PROPAGATE.ANALYTICS.EVENT_LOG b
  ON a.event_type='WAREHOUSE_BACKLOG' AND b.event_type='ORDER_DELIVERY'
 AND a.link_warehouse_id = b.link_warehouse_id
 AND b.event_time > a.event_time
 AND DATEDIFF('day',a.event_time,b.event_time) <= 14
 AND a.deviation_score >= 1.0
 AND b.magnitude > 0;

INSERT INTO PROPAGATE.ANALYTICS.CANDIDATE_EDGES
SELECT a.event_id||'->'||b.event_id, a.event_id, b.event_id, a.event_type, b.event_type,
       a.business_function, b.business_function, 'LATE_DELIVERY_PRECEDES_COMPLAINT',
       DATEDIFF('day',a.event_time,b.event_time), DATEDIFF('hour',a.event_time,b.event_time),
       'ORDER', a.link_order_id
FROM PROPAGATE.ANALYTICS.EVENT_LOG a
JOIN PROPAGATE.ANALYTICS.EVENT_LOG b
  ON a.event_type='ORDER_DELIVERY' AND b.event_type='SUPPORT_TICKET'
 AND a.link_order_id = b.link_order_id AND a.link_order_id IS NOT NULL
 AND b.event_time >= a.event_time
 AND DATEDIFF('day',a.event_time,b.event_time) <= 7;

INSERT INTO PROPAGATE.ANALYTICS.CANDIDATE_EDGES
SELECT a.event_id||'->'||b.event_id, a.event_id, b.event_id, a.event_type, b.event_type,
       a.business_function, b.business_function, 'COMPLAINT_ASSOCIATED_WITH_REFUND',
       DATEDIFF('day',a.event_time,b.event_time), DATEDIFF('hour',a.event_time,b.event_time),
       'ORDER', a.link_order_id
FROM PROPAGATE.ANALYTICS.EVENT_LOG a
JOIN PROPAGATE.ANALYTICS.EVENT_LOG b
  ON a.event_type='SUPPORT_TICKET' AND b.event_type='REFUND'
 AND a.link_order_id = b.link_order_id AND a.link_order_id IS NOT NULL
 AND b.event_time >= a.event_time
 AND DATEDIFF('day',a.event_time,b.event_time) <= 10;

INSERT INTO PROPAGATE.ANALYTICS.CANDIDATE_EDGES
SELECT a.event_id||'->'||b.event_id, a.event_id, b.event_id, a.event_type, b.event_type,
       a.business_function, b.business_function, 'REFUNDS_ASSOCIATED_WITH_REVENUE_IMPACT',
       DATEDIFF('day',a.event_time,b.event_time), DATEDIFF('hour',a.event_time,b.event_time),
       'REGION', a.link_region
FROM PROPAGATE.ANALYTICS.EVENT_LOG a
JOIN PROPAGATE.ANALYTICS.EVENT_LOG b
  ON a.event_type='REFUND' AND b.event_type='REVENUE'
 AND a.link_region = b.link_region
 AND b.event_time > a.event_time
 AND DATEDIFF('day',a.event_time,b.event_time) <= 14
 AND b.deviation_score <= -1.0;

-- ===================================================================
-- STEP D: Rebuild SCORED_EDGES (from 06_evidence_scorer.sql — verbatim)
-- ===================================================================
CREATE OR REPLACE TABLE PROPAGATE.ANALYTICS.SCORED_EDGES AS
WITH comp AS (
  SELECT
    ce.edge_id, ce.from_event, ce.to_event, ce.from_type, ce.to_type,
    ce.from_function, ce.to_function, ce.relation, ce.lag_days, ce.lag_hours,
    ce.shared_entity_type, ce.shared_entity_id,
    af.event_time AS from_time, at.event_time AS to_time,
    GREATEST(0, 1 - ce.lag_days / l.max_lag_days) AS comp_temporal,
    CASE ce.shared_entity_type
      WHEN 'ORDER' THEN 1.0 WHEN 'SUPPLIER' THEN 0.8 WHEN 'WAREHOUSE' THEN 0.7
      WHEN 'REGION' THEN 0.5 ELSE 0.4 END AS comp_structural,
    ( IFF(af.deviation_score IS NOT NULL, LEAST(1, ABS(af.deviation_score)/3.0),
        IFF(af.event_type='SUPPORT_TICKET', GREATEST(0, -COALESCE(dsf.sentiment,0)),
        IFF(af.event_type='SCHEDULE_CHANGE', IFF(COALESCE(dsf.asserts_cause,FALSE),1.0,0.3), 0)))
    + IFF(at.deviation_score IS NOT NULL, LEAST(1, ABS(at.deviation_score)/3.0),
        IFF(at.event_type='SUPPORT_TICKET', GREATEST(0, -COALESCE(dst.sentiment,0)),
        IFF(at.event_type='SCHEDULE_CHANGE', IFF(COALESCE(dst.asserts_cause,FALSE),1.0,0.3), 0)))
    ) / 2.0 AS comp_magnitude,
    CASE ce.relation
      WHEN 'SCHEDULE_CHANGE_PRECEDES_DELAY' THEN IFF(COALESCE(dsf.asserts_cause,FALSE),1.0,0.2)
      WHEN 'LATE_DELIVERY_PRECEDES_COMPLAINT' THEN
        CASE COALESCE(dst.label,'OTHER') WHEN 'LATE_DELIVERY_COMPLAINT' THEN 1.0
             WHEN 'PRAISE' THEN 0.0 WHEN 'DAMAGE_COMPLAINT' THEN 0.4 ELSE 0.3 END
      WHEN 'COMPLAINT_ASSOCIATED_WITH_REFUND' THEN IFF(COALESCE(dsf.label,'')='LATE_DELIVERY_COMPLAINT',0.8,0.3)
      ELSE 0 END AS comp_textual,
    ( SELECT COUNT(DISTINCT TO_CHAR(e2.event_time,'YYYY-MM'))
        FROM PROPAGATE.ANALYTICS.CANDIDATE_EDGES c2
        JOIN PROPAGATE.ANALYTICS.EVENT_LOG e2 ON e2.event_id = c2.from_event
       WHERE c2.relation = ce.relation AND c2.shared_entity_id = ce.shared_entity_id
         AND TO_CHAR(e2.event_time,'YYYY-MM') <> TO_CHAR(af.event_time,'YYYY-MM') ) AS historical_count,
    COALESCE(dsf.asserts_cause,FALSE) AS from_asserts_cause
  FROM PROPAGATE.ANALYTICS.CANDIDATE_EDGES ce
  JOIN PROPAGATE.ANALYTICS.EVENT_LOG af ON af.event_id = ce.from_event
  JOIN PROPAGATE.ANALYTICS.EVENT_LOG at ON at.event_id = ce.to_event
  JOIN PROPAGATE.ANALYTICS.LAG_WINDOWS l ON l.relation = ce.relation
  LEFT JOIN PROPAGATE.ANALYTICS.DOC_SIGNALS dsf ON dsf.doc_id = af.text_ref
  LEFT JOIN PROPAGATE.ANALYTICS.DOC_SIGNALS dst ON dst.doc_id = at.text_ref
)
SELECT
  comp.* EXCLUDE (historical_count, from_asserts_cause),
  LEAST(1, historical_count/2.0) AS comp_historical,
  ROUND(0.15*comp_temporal + 0.15*comp_structural + 0.20*comp_magnitude
      + 0.25*comp_textual + 0.25*LEAST(1, historical_count/2.0), 4) AS evidence_score,
  CASE
    WHEN relation='SCHEDULE_CHANGE_PRECEDES_DELAY' AND from_asserts_cause THEN 'CAUSAL_STATED'
    WHEN comp_textual >= 0.5 THEN 'TEXT_SUPPORTED'
    WHEN LEAST(1, historical_count/2.0) >= 0.5 THEN 'HISTORICAL_SUPPORTED'
    WHEN comp_temporal > 0 AND comp_structural > 0 THEN 'TEMPORAL_STRUCTURAL'
    ELSE 'CORRELATION_ONLY' END AS evidence_class,
  (0.15*comp_temporal + 0.15*comp_structural + 0.20*comp_magnitude
      + 0.25*comp_textual + 0.25*LEAST(1, historical_count/2.0)) >= 0.40 AS retained
FROM comp;

-- ===================================================================
-- STEP E: Rebuild CHAIN_EDGES + CHAINS (from 07_chain_builder.sql — verbatim)
-- ===================================================================
CREATE OR REPLACE TABLE PROPAGATE.ANALYTICS.CHAIN_EDGES AS
WITH best_parent AS (
  SELECT edge_id, from_event, to_event, relation, evidence_score, evidence_class, lag_days
  FROM PROPAGATE.ANALYTICS.SCORED_EDGES
  WHERE retained
  QUALIFY ROW_NUMBER() OVER (PARTITION BY to_event ORDER BY evidence_score DESC, lag_days ASC) = 1
),
walk AS (
  SELECT bp.to_event AS anchor, 1 AS depth, bp.edge_id, bp.from_event, bp.to_event,
         bp.relation, bp.evidence_score, bp.evidence_class
  FROM best_parent bp
  WHERE bp.to_event LIKE 'EVT_BM_%'
  UNION ALL
  SELECT w.anchor, w.depth+1, bp.edge_id, bp.from_event, bp.to_event,
         bp.relation, bp.evidence_score, bp.evidence_class
  FROM walk w JOIN best_parent bp ON bp.to_event = w.from_event
),
anchor_summary AS (
  SELECT anchor, COUNT(*) nedges, SUM(evidence_score) total_score, MAX(depth) maxdepth
  FROM walk GROUP BY anchor
),
anchor_root AS (
  SELECT w.anchor, w.from_event AS root_event
  FROM walk w JOIN anchor_summary s ON s.anchor=w.anchor AND w.depth=s.maxdepth
),
chosen AS (
  SELECT a.anchor, ar.root_event, a.total_score, a.nedges, a.maxdepth
  FROM anchor_summary a JOIN anchor_root ar ON ar.anchor=a.anchor
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ar.root_event ORDER BY a.total_score DESC, a.nedges DESC) = 1
)
SELECT 'CHAIN_'||REPLACE(c.root_event,'EVT_SC_','') AS chain_id,
       (c.maxdepth - w.depth + 1) AS step_no,
       w.edge_id, w.from_event, w.to_event, w.relation, w.evidence_score, w.evidence_class
FROM chosen c JOIN walk w ON w.anchor = c.anchor;

CREATE OR REPLACE TABLE PROPAGATE.ANALYTICS.CHAINS AS
WITH ce AS (
  SELECT *, MIN(step_no) OVER (PARTITION BY chain_id) mins, MAX(step_no) OVER (PARTITION BY chain_id) maxs
  FROM PROPAGATE.ANALYTICS.CHAIN_EDGES
),
agg AS (
  SELECT chain_id,
    MAX(IFF(step_no=mins, from_event, NULL)) AS root_event,
    MAX(IFF(step_no=maxs, to_event,  NULL)) AS impact_event,
    COUNT(*) AS edge_count, COUNT(*)+1 AS node_count,
    ROUND(SUM(evidence_score),4) AS total_score,
    ROUND(MIN(evidence_score),4) AS min_edge_score,
    ROUND(AVG(evidence_score),4) AS avg_edge_score,
    BOOLAND_AGG(evidence_class IN ('CAUSAL_STATED','TEXT_SUPPORTED','HISTORICAL_SUPPORTED')) AS all_edges_supported
  FROM ce GROUP BY chain_id
),
nodes AS (
  SELECT c.chain_id, COUNT(DISTINCT el.entity_id) AS affected_entity_count
  FROM PROPAGATE.ANALYTICS.CHAIN_EDGES c
  JOIN PROPAGATE.ANALYTICS.EVENT_LOG el ON el.event_id IN (c.from_event, c.to_event)
  GROUP BY c.chain_id
)
SELECT a.chain_id, a.root_event, re.event_type AS root_type, re.event_time AS root_time,
       re.business_function AS earliest_signal_function,
       a.impact_event, ie.event_type AS impact_type, ie.event_time AS impact_time, ie.link_region AS impact_region,
       a.edge_count, a.node_count, n.affected_entity_count,
       a.total_score, a.min_edge_score, a.avg_edge_score, a.all_edges_supported,
       a.root_event AS earliest_intervention_event,
       re.business_function AS intervention_function,
       DATEDIFF('day', re.event_time, ie.event_time) AS intervention_lead_days,
       CURRENT_TIMESTAMP() AS created_at
FROM agg a
JOIN PROPAGATE.ANALYTICS.EVENT_LOG re ON re.event_id = a.root_event
JOIN PROPAGATE.ANALYTICS.EVENT_LOG ie ON ie.event_id = a.impact_event
JOIN nodes n ON n.chain_id = a.chain_id;
