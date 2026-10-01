-- PROPAGATE :: Phase 2 :: 04_event_spine.sql
-- Normalizes every structured + doc event into one typed timeline with deviation scores.
-- Deviation model:
--   * Daily series (warehouse backlog, revenue): z-score vs that entity's own 122-day baseline  -> STRONG signal.
--   * Discrete events (shipment delay, order lateness, refund amount): z-score across all rows of the type.
--   * Doc events (supplier comm, support ticket): magnitude/deviation left NULL here; enriched in Phase 4 (AI).
-- Link columns are denormalized so Phase 3 candidate-linking is pure SQL on EVENT_LOG.

CREATE OR REPLACE TABLE PROPAGATE.ANALYTICS.EVENT_LOG (
  event_id STRING PRIMARY KEY,
  event_time TIMESTAMP_NTZ,
  event_type STRING,            -- SCHEDULE_CHANGE, SHIPMENT_DELAY, WAREHOUSE_BACKLOG, ORDER_DELIVERY, SUPPORT_TICKET, REFUND, REVENUE
  business_function STRING,     -- SUPPLIER, SHIPPING, WAREHOUSE, FULFILLMENT, SUPPORT, FINANCE
  entity_type STRING,
  entity_id STRING,
  magnitude FLOAT,
  deviation_score FLOAT,
  link_supplier_id STRING,
  link_warehouse_id STRING,
  link_customer_id STRING,
  link_order_id STRING,
  link_shipment_id STRING,
  link_region STRING,
  source_table STRING,
  source_ref STRING,
  text_ref STRING
);

-- 1) SUPPLIER COMMS (root signals; magnitude/deviation enriched in Phase 4)
INSERT INTO PROPAGATE.ANALYTICS.EVENT_LOG
SELECT 'EVT_SC_'||sc.doc_id, sc.event_time, 'SCHEDULE_CHANGE','SUPPLIER','SUPPLIER', sc.entity_ref,
       NULL, NULL,
       sc.entity_ref, sc.warehouse_ref, NULL, NULL, NULL, w.region,
       'DOCS.SUPPLIER_COMMS', sc.doc_id, sc.doc_id
FROM PROPAGATE.DOCS.SUPPLIER_COMMS sc
LEFT JOIN PROPAGATE.CORE.WAREHOUSES w ON w.warehouse_id = sc.warehouse_ref;

-- 2) SHIPMENT DELAYS (event_time = planned/expected arrival, when the slip becomes observable)
INSERT INTO PROPAGATE.ANALYTICS.EVENT_LOG
SELECT 'EVT_SH_'||s.shipment_id, s.planned_date::timestamp_ntz, 'SHIPMENT_DELAY','SHIPPING','SHIPMENT', s.shipment_id,
       s.delay_days,
       (s.delay_days - AVG(s.delay_days) OVER ()) / NULLIF(STDDEV_POP(s.delay_days) OVER (),0),
       s.supplier_id, s.dest_wh, NULL, NULL, s.shipment_id, w.region,
       'CORE.SHIPMENTS', s.shipment_id, NULL
FROM PROPAGATE.CORE.SHIPMENTS s
LEFT JOIN PROPAGATE.CORE.WAREHOUSES w ON w.warehouse_id = s.dest_wh;

-- 3) WAREHOUSE DAILY BACKLOG (z vs per-warehouse baseline)
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

-- 4) ORDERS (lateness days; event_time = delivered_date)
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

-- 5) SUPPORT TICKETS (sentiment magnitude added in Phase 4)
INSERT INTO PROPAGATE.ANALYTICS.EVENT_LOG
SELECT 'EVT_ST_'||t.doc_id, t.event_time, 'SUPPORT_TICKET','SUPPORT','SUPPORT_TICKET', t.doc_id,
       NULL, NULL,
       s.supplier_id, o.warehouse_id, t.entity_ref, t.order_ref, o.shipment_id, c.region,
       'DOCS.SUPPORT_TICKETS', t.doc_id, t.doc_id
FROM PROPAGATE.DOCS.SUPPORT_TICKETS t
LEFT JOIN PROPAGATE.CORE.ORDERS o ON o.order_id = t.order_ref
LEFT JOIN PROPAGATE.CORE.CUSTOMERS c ON c.customer_id = t.entity_ref
LEFT JOIN PROPAGATE.CORE.SHIPMENTS s ON s.shipment_id = o.shipment_id;

-- 6) REFUNDS (amount; z across all refunds)
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

-- 7) BUSINESS METRICS / REVENUE (z vs per-region baseline; dips = strong negative deviation)
INSERT INTO PROPAGATE.ANALYTICS.EVENT_LOG
SELECT 'EVT_BM_'||b.region||'_'||TO_VARCHAR(b.metric_date,'YYYYMMDD'), b.metric_date::timestamp_ntz,
       'REVENUE','FINANCE','BUSINESS_METRIC', b.region,
       b.revenue,
       (b.revenue - AVG(b.revenue) OVER (PARTITION BY b.region))
         / NULLIF(STDDEV_POP(b.revenue) OVER (PARTITION BY b.region),0),
       NULL, NULL, NULL, NULL, NULL, b.region,
       'CORE.BUSINESS_METRICS', b.region||'|'||TO_VARCHAR(b.metric_date,'YYYY-MM-DD'), NULL
FROM PROPAGATE.CORE.BUSINESS_METRICS b;
