-- PROPAGATE :: Phase 3 :: 05_candidate_linker.sql
-- Generates CANDIDATE propagation edges from observable signals only (NO causal claim yet).
-- An edge A->B is a candidate when ALL hold:
--   (1) transition (A.function -> B.function) is in the allowed domain graph (LAG_WINDOWS)
--   (2) temporal precedence: A before B, within the transition's max lag
--   (3) shared entity along a known key path
--   (4) observability gate on daily-series nodes: |deviation_score| >= 1.0 (keeps spikes/dips, drops flat days)
-- Recall-focused: distractors MAY appear here; they are pruned by evidence scoring in Phase 4.

-- ---------- config: allowed transitions + lag windows (inspectable by UI/agent) ----------
CREATE OR REPLACE TABLE PROPAGATE.ANALYTICS.LAG_WINDOWS (
  step_no NUMBER, from_type STRING, to_type STRING, from_function STRING, to_function STRING,
  relation STRING, max_lag_days NUMBER, shared_key STRING
);
INSERT INTO PROPAGATE.ANALYTICS.LAG_WINDOWS VALUES
 (1,'SCHEDULE_CHANGE','SHIPMENT_DELAY','SUPPLIER','SHIPPING','SCHEDULE_CHANGE_PRECEDES_DELAY',14,'SUPPLIER(+WAREHOUSE)'),
 (2,'SHIPMENT_DELAY','WAREHOUSE_BACKLOG','SHIPPING','WAREHOUSE','DELAY_PRECEDES_BACKLOG',10,'WAREHOUSE'),
 (3,'WAREHOUSE_BACKLOG','ORDER_DELIVERY','WAREHOUSE','FULFILLMENT','BACKLOG_PRECEDES_LATE_DELIVERY',14,'WAREHOUSE'),
 (4,'ORDER_DELIVERY','SUPPORT_TICKET','FULFILLMENT','SUPPORT','LATE_DELIVERY_PRECEDES_COMPLAINT',7,'ORDER'),
 (5,'SUPPORT_TICKET','REFUND','SUPPORT','FINANCE','COMPLAINT_ASSOCIATED_WITH_REFUND',10,'ORDER'),
 (6,'REFUND','REVENUE','FINANCE','FINANCE','REFUNDS_ASSOCIATED_WITH_REVENUE_IMPACT',14,'REGION');

-- ---------- candidate edges ----------
CREATE OR REPLACE TABLE PROPAGATE.ANALYTICS.CANDIDATE_EDGES (
  edge_id STRING, from_event STRING, to_event STRING,
  from_type STRING, to_type STRING, from_function STRING, to_function STRING,
  relation STRING, lag_days FLOAT, lag_hours FLOAT,
  shared_entity_type STRING, shared_entity_id STRING
);

-- T1: SCHEDULE_CHANGE -> SHIPMENT_DELAY  (shared supplier; warehouse matches or comm has none)
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

-- T2: SHIPMENT_DELAY -> WAREHOUSE_BACKLOG  (shared warehouse; target spike |dev|>=1)
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

-- T3: WAREHOUSE_BACKLOG -> ORDER_DELIVERY  (shared warehouse; source spike dev>=1; target late order)
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

-- T4: ORDER_DELIVERY -> SUPPORT_TICKET  (shared order)
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

-- T5: SUPPORT_TICKET -> REFUND  (shared order)
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

-- T6: REFUND -> REVENUE  (shared region; target dip dev<=-1)
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
