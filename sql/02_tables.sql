-- PROPAGATE :: Phase 1 :: 02_tables.sql
-- Minimum-viable data model. MVP unstructured sources = SUPPLIER_COMMS + SUPPORT_TICKETS.
-- Designed so INCIDENT_REPORTS + WAREHOUSE_REPORTS can be added later with no restructuring:
--   both are doc tables with (doc_id, doc_type, entity_ref, event_time, body_text) shape.

-- ========== CORE (structured) ==========
CREATE OR REPLACE TABLE PROPAGATE.CORE.SUPPLIERS (
  supplier_id STRING PRIMARY KEY, name STRING, region STRING, tier STRING
);

CREATE OR REPLACE TABLE PROPAGATE.CORE.WAREHOUSES (
  warehouse_id STRING PRIMARY KEY, name STRING, region STRING, capacity_units NUMBER
);

CREATE OR REPLACE TABLE PROPAGATE.CORE.CUSTOMERS (
  customer_id STRING PRIMARY KEY, name STRING, segment STRING, region STRING
);

CREATE OR REPLACE TABLE PROPAGATE.CORE.SHIPMENTS (
  shipment_id STRING PRIMARY KEY, supplier_id STRING, origin_wh STRING, dest_wh STRING,
  planned_date DATE, actual_date DATE, delay_days NUMBER, status STRING
);

CREATE OR REPLACE TABLE PROPAGATE.CORE.WAREHOUSE_DAILY (
  warehouse_id STRING, date DATE, backlog_units NUMBER, throughput_units NUMBER, utilization_pct FLOAT
);

CREATE OR REPLACE TABLE PROPAGATE.CORE.ORDERS (
  order_id STRING PRIMARY KEY, customer_id STRING, warehouse_id STRING, shipment_id STRING,
  order_date DATE, promised_date DATE, delivered_date DATE, late_flag BOOLEAN
);

CREATE OR REPLACE TABLE PROPAGATE.CORE.REFUNDS (
  refund_id STRING PRIMARY KEY, order_id STRING, refund_date DATE, amount NUMBER(12,2), reason_code STRING
);

CREATE OR REPLACE TABLE PROPAGATE.CORE.BUSINESS_METRICS (
  metric_date DATE, region STRING, revenue NUMBER(14,2), repeat_purchase_rate FLOAT, support_ticket_count NUMBER
);

-- ========== DOCS (unstructured, MVP = 2 sources) ==========
CREATE OR REPLACE TABLE PROPAGATE.DOCS.SUPPLIER_COMMS (
  doc_id STRING PRIMARY KEY, doc_type STRING DEFAULT 'SUPPLIER_COMM',
  entity_ref STRING,            -- supplier_id (loose link)
  warehouse_ref STRING,         -- optional affected warehouse mentioned in the comm
  event_time TIMESTAMP_NTZ, body_text STRING
);

CREATE OR REPLACE TABLE PROPAGATE.DOCS.SUPPORT_TICKETS (
  doc_id STRING PRIMARY KEY, doc_type STRING DEFAULT 'SUPPORT_TICKET',
  entity_ref STRING,            -- customer_id (loose link)
  order_ref STRING,             -- optional order_id
  event_time TIMESTAMP_NTZ, body_text STRING
);

-- ========== ANALYTICS (ground truth for validation) ==========
-- One row per TRUE directed relationship in a seeded chain. Distractor edges are NOT recorded here,
-- so false-link rate = engine edges that are not present in GROUND_TRUTH_EDGES.
CREATE OR REPLACE TABLE PROPAGATE.ANALYTICS.GROUND_TRUTH_EDGES (
  chain_label STRING,           -- e.g. GOLDEN_2026_09, HIST_2026_06, HIST_2026_07
  step_no NUMBER,               -- order within the chain
  from_type STRING, from_id STRING,
  to_type STRING,   to_id STRING,
  relation STRING,              -- e.g. SCHEDULE_CHANGE_CAUSES_DELAY
  is_root BOOLEAN,              -- true for the earliest signal node of the chain
  is_impact BOOLEAN             -- true for the terminal business-impact node
);
