-- PROPAGATE :: Phase 1 :: 03_seed.sql
-- Deterministic synthetic generator. Fully formula-based (no RNG) => bit-for-bit reproducible.
-- Contents:
--   * Dimensions: suppliers, warehouses, customers
--   * GOLDEN chain  (GOLDEN_2026_09): SUP-ACME schedule change -> WH-WEST backlog -> late orders
--                   -> complaints -> refunds -> west revenue dip
--   * HISTORY       (HIST_2026_06, HIST_2026_07): smaller analogues of the same chain (recurrence)
--   * DISTRACTORS   (not in ground truth): on-schedule supplier comm, unrelated WH-EAST late order,
--                   praise ticket, non-late refund, east promo revenue blip
-- Re-runnable: truncates fact/doc tables first.

TRUNCATE TABLE IF EXISTS PROPAGATE.CORE.SHIPMENTS;
TRUNCATE TABLE IF EXISTS PROPAGATE.CORE.WAREHOUSE_DAILY;
TRUNCATE TABLE IF EXISTS PROPAGATE.CORE.ORDERS;
TRUNCATE TABLE IF EXISTS PROPAGATE.CORE.REFUNDS;
TRUNCATE TABLE IF EXISTS PROPAGATE.CORE.BUSINESS_METRICS;
TRUNCATE TABLE IF EXISTS PROPAGATE.DOCS.SUPPLIER_COMMS;
TRUNCATE TABLE IF EXISTS PROPAGATE.DOCS.SUPPORT_TICKETS;
TRUNCATE TABLE IF EXISTS PROPAGATE.ANALYTICS.GROUND_TRUTH_EDGES;

-- ===================== DIMENSIONS =====================
INSERT INTO PROPAGATE.CORE.SUPPLIERS VALUES
 ('SUP-ACME','Acme Components','west','TIER1'),
 ('SUP-BETA','Beta Logistics','east','TIER2'),
 ('SUP-GAMMA','Gamma Parts','west','TIER2'),
 ('SUP-DELTA','Delta Freight','central','TIER1');

INSERT INTO PROPAGATE.CORE.WAREHOUSES VALUES
 ('WH-WEST','West DC','west',10000),
 ('WH-EAST','East DC','east',8000),
 ('WH-CENTRAL','Central DC','central',9000);

INSERT INTO PROPAGATE.CORE.CUSTOMERS VALUES
 ('CUST-101','Northwind Retail','ENTERPRISE','west'),
 ('CUST-102','Cascade Goods','SMB','west'),
 ('CUST-103','Pacific Supply','ENTERPRISE','west'),
 ('CUST-104','Rainier Stores','SMB','west'),
 ('CUST-105','Atlantic Mart','ENTERPRISE','east'),
 ('CUST-106','Harbor Shops','SMB','east'),
 ('CUST-107','Prairie Depot','ENTERPRISE','central'),
 ('CUST-108','Plains Outlet','SMB','central');

-- ===================== UNSTRUCTURED DOCS =====================
INSERT INTO PROPAGATE.DOCS.SUPPLIER_COMMS (doc_id, entity_ref, warehouse_ref, event_time, body_text) VALUES
 ('SC-G1','SUP-ACME','WH-WEST','2026-09-01 09:00','Notice: due to a port closure we are moving your delivery window for WH-WEST back by approximately 10 days. All inbound shipments this week are affected.'),
 ('SC-H1','SUP-ACME','WH-WEST','2026-06-05 09:00','Advisory: a customs hold will delay WH-WEST inbound shipments by about one week this cycle.'),
 ('SC-H2','SUP-ACME','WH-WEST','2026-07-10 09:00','Update: equipment failure at origin will push WH-WEST deliveries back roughly 8 days.'),
 ('SC-D1','SUP-BETA','WH-EAST','2026-09-02 11:00','Routine confirmation: your WH-EAST shipment is on schedule. No changes to the delivery window.');

INSERT INTO PROPAGATE.DOCS.SUPPORT_TICKETS (doc_id, entity_ref, order_ref, event_time, body_text) VALUES
 ('ST-G1','CUST-101','OR-G1','2026-09-14 14:00','My order is almost two weeks late and no one informed me. This is unacceptable, I want a refund.'),
 ('ST-G2','CUST-102','OR-G2','2026-09-15 10:30','Extremely delayed delivery. Still waiting far past the promised date. Requesting a refund.'),
 ('ST-G3','CUST-103','OR-G3','2026-09-15 16:00','The shipment arrived very late and disrupted our operations. Very disappointed.'),
 ('ST-G4','CUST-104','OR-G4','2026-09-16 09:15','Late again. Promised date was days ago. Please refund the order.'),
 ('ST-H1','CUST-101','OR-H1','2026-06-15 12:00','Order delivered a week late. Frustrated and considering a refund.'),
 ('ST-H2','CUST-103','OR-H2','2026-07-21 12:00','Shipment arrived over a week late, this keeps happening. Want a refund.'),
 ('ST-D1','CUST-105','OR-D1','2026-09-11 13:00','Delivery was a few days late, apparently due to a storm in the region.'),
 ('ST-D2','CUST-107',NULL,'2026-09-15 11:00','Great service and fast delivery this month, very satisfied!');

-- ===================== CORE FACTS (curated) =====================
INSERT INTO PROPAGATE.CORE.SHIPMENTS VALUES
 ('SH-G1','SUP-ACME','SUP-HUB-W','WH-WEST','2026-09-03','2026-09-13',10,'LATE'),
 ('SH-G2','SUP-ACME','SUP-HUB-W','WH-WEST','2026-09-04','2026-09-15',11,'LATE'),
 ('SH-G3','SUP-ACME','SUP-HUB-W','WH-WEST','2026-09-05','2026-09-16',11,'LATE'),
 ('SH-H1','SUP-ACME','SUP-HUB-W','WH-WEST','2026-06-07','2026-06-14',7,'LATE'),
 ('SH-H2','SUP-ACME','SUP-HUB-W','WH-WEST','2026-07-12','2026-07-20',8,'LATE'),
 ('SH-D1','SUP-BETA','SUP-HUB-E','WH-EAST','2026-09-05','2026-09-09',4,'LATE'),
 ('SH-D2','SUP-BETA','SUP-HUB-E','WH-EAST','2026-09-05','2026-09-11',0,'ON_TIME');

INSERT INTO PROPAGATE.CORE.ORDERS VALUES
 ('OR-G1','CUST-101','WH-WEST','SH-G1','2026-09-02','2026-09-10','2026-09-14',TRUE),
 ('OR-G2','CUST-102','WH-WEST','SH-G2','2026-09-02','2026-09-10','2026-09-15',TRUE),
 ('OR-G3','CUST-103','WH-WEST','SH-G3','2026-09-02','2026-09-10','2026-09-15',TRUE),
 ('OR-G4','CUST-104','WH-WEST','SH-G1','2026-09-02','2026-09-10','2026-09-16',TRUE),
 ('OR-H1','CUST-101','WH-WEST','SH-H1','2026-06-06','2026-06-12','2026-06-15',TRUE),
 ('OR-H2','CUST-103','WH-WEST','SH-H2','2026-07-11','2026-07-18','2026-07-21',TRUE),
 ('OR-D1','CUST-105','WH-EAST','SH-D1','2026-09-03','2026-09-08','2026-09-11',TRUE),
 ('OR-D2','CUST-106','WH-EAST','SH-D2','2026-09-05','2026-09-12','2026-09-11',FALSE);

INSERT INTO PROPAGATE.CORE.REFUNDS VALUES
 ('RF-G1','OR-G1','2026-09-16',1200.00,'LATE_DELIVERY'),
 ('RF-G2','OR-G2','2026-09-17',640.00,'LATE_DELIVERY'),
 ('RF-G3','OR-G3','2026-09-18',1500.00,'LATE_DELIVERY'),
 ('RF-G4','OR-G4','2026-09-19',700.00,'LATE_DELIVERY'),
 ('RF-H1','OR-H1','2026-06-17',900.00,'LATE_DELIVERY'),
 ('RF-H2','OR-H2','2026-07-23',1100.00,'LATE_DELIVERY'),
 ('RF-D1','OR-D2','2026-09-13',300.00,'DAMAGED');

-- ===================== DAILY SERIES (baseline + injected spikes/dips) =====================
INSERT INTO PROPAGATE.CORE.WAREHOUSE_DAILY (warehouse_id, date, backlog_units, throughput_units, utilization_pct)
SELECT w.warehouse_id, DATEADD('day', g.seq, '2026-06-01')::date,
       450 + MOD(g.seq,7)*20, 500, ROUND(100.0*(450 + MOD(g.seq,7)*20)/w.capacity_units, 2)
FROM PROPAGATE.CORE.WAREHOUSES w
CROSS JOIN (SELECT SEQ4() AS seq FROM TABLE(GENERATOR(ROWCOUNT => 122))) g;

UPDATE PROPAGATE.CORE.WAREHOUSE_DAILY
   SET backlog_units = 1900 + 90*MOD(DATEDIFF('day','2026-09-05',date),10),
       utilization_pct = ROUND(100.0*(1900 + 90*MOD(DATEDIFF('day','2026-09-05',date),10))/10000, 2)
 WHERE warehouse_id='WH-WEST' AND date BETWEEN '2026-09-05' AND '2026-09-14';
UPDATE PROPAGATE.CORE.WAREHOUSE_DAILY
   SET backlog_units = 1150 + 60*MOD(DATEDIFF('day','2026-06-10',date),7),
       utilization_pct = ROUND(100.0*(1150 + 60*MOD(DATEDIFF('day','2026-06-10',date),7))/10000, 2)
 WHERE warehouse_id='WH-WEST' AND date BETWEEN '2026-06-10' AND '2026-06-16';
UPDATE PROPAGATE.CORE.WAREHOUSE_DAILY
   SET backlog_units = 1200 + 60*MOD(DATEDIFF('day','2026-07-12',date),7),
       utilization_pct = ROUND(100.0*(1200 + 60*MOD(DATEDIFF('day','2026-07-12',date),7))/10000, 2)
 WHERE warehouse_id='WH-WEST' AND date BETWEEN '2026-07-12' AND '2026-07-18';

INSERT INTO PROPAGATE.CORE.BUSINESS_METRICS (metric_date, region, revenue, repeat_purchase_rate, support_ticket_count)
SELECT DATEADD('day', g.seq, '2026-06-01')::date, r.region,
       r.base + MOD(g.seq,7)*2000, 0.62, 5 + MOD(g.seq,5)
FROM (SELECT 'west' region, 120000 base UNION ALL SELECT 'east',90000 UNION ALL SELECT 'central',100000) r
CROSS JOIN (SELECT SEQ4() AS seq FROM TABLE(GENERATOR(ROWCOUNT => 122))) g;

UPDATE PROPAGATE.CORE.BUSINESS_METRICS
   SET revenue = 84000 + MOD(DATEDIFF('day','2026-09-18',metric_date),4)*1500,
       repeat_purchase_rate = 0.50, support_ticket_count = 25
 WHERE region='west' AND metric_date BETWEEN '2026-09-18' AND '2026-09-25';
UPDATE PROPAGATE.CORE.BUSINESS_METRICS
   SET revenue = 102000, repeat_purchase_rate = 0.56, support_ticket_count = 15
 WHERE region='west' AND metric_date BETWEEN '2026-06-18' AND '2026-06-24';
UPDATE PROPAGATE.CORE.BUSINESS_METRICS
   SET revenue = 103000, repeat_purchase_rate = 0.57, support_ticket_count = 14
 WHERE region='west' AND metric_date BETWEEN '2026-07-23' AND '2026-07-29';
UPDATE PROPAGATE.CORE.BUSINESS_METRICS
   SET revenue = 112000, support_ticket_count = 4
 WHERE region='east' AND metric_date BETWEEN '2026-09-14' AND '2026-09-18';

-- ===================== GROUND TRUTH =====================
INSERT INTO PROPAGATE.ANALYTICS.GROUND_TRUTH_EDGES
 (chain_label, step_no, from_type, from_id, to_type, to_id, relation, is_root, is_impact) VALUES
 ('GOLDEN_2026_09',1,'SUPPLIER_COMM','SC-G1','SHIPMENT','SH-G1','SCHEDULE_CHANGE_PRECEDES_DELAY',TRUE,FALSE),
 ('GOLDEN_2026_09',2,'SHIPMENT','SH-G1','WAREHOUSE','WH-WEST','DELAY_PRECEDES_BACKLOG',FALSE,FALSE),
 ('GOLDEN_2026_09',3,'WAREHOUSE','WH-WEST','ORDER','OR-G1','BACKLOG_PRECEDES_LATE_DELIVERY',FALSE,FALSE),
 ('GOLDEN_2026_09',4,'ORDER','OR-G1','SUPPORT_TICKET','ST-G1','LATE_DELIVERY_PRECEDES_COMPLAINT',FALSE,FALSE),
 ('GOLDEN_2026_09',5,'SUPPORT_TICKET','ST-G1','REFUND','RF-G1','COMPLAINT_ASSOCIATED_WITH_REFUND',FALSE,FALSE),
 ('GOLDEN_2026_09',6,'REFUND','RF-G1','BUSINESS_METRIC','west:2026-09','REFUNDS_ASSOCIATED_WITH_REVENUE_IMPACT',FALSE,TRUE),
 ('HIST_2026_06',1,'SUPPLIER_COMM','SC-H1','SHIPMENT','SH-H1','SCHEDULE_CHANGE_PRECEDES_DELAY',TRUE,FALSE),
 ('HIST_2026_06',2,'SHIPMENT','SH-H1','WAREHOUSE','WH-WEST','DELAY_PRECEDES_BACKLOG',FALSE,FALSE),
 ('HIST_2026_06',3,'WAREHOUSE','WH-WEST','ORDER','OR-H1','BACKLOG_PRECEDES_LATE_DELIVERY',FALSE,FALSE),
 ('HIST_2026_06',4,'ORDER','OR-H1','SUPPORT_TICKET','ST-H1','LATE_DELIVERY_PRECEDES_COMPLAINT',FALSE,FALSE),
 ('HIST_2026_06',5,'SUPPORT_TICKET','ST-H1','REFUND','RF-H1','COMPLAINT_ASSOCIATED_WITH_REFUND',FALSE,FALSE),
 ('HIST_2026_06',6,'REFUND','RF-H1','BUSINESS_METRIC','west:2026-06','REFUNDS_ASSOCIATED_WITH_REVENUE_IMPACT',FALSE,TRUE),
 ('HIST_2026_07',1,'SUPPLIER_COMM','SC-H2','SHIPMENT','SH-H2','SCHEDULE_CHANGE_PRECEDES_DELAY',TRUE,FALSE),
 ('HIST_2026_07',2,'SHIPMENT','SH-H2','WAREHOUSE','WH-WEST','DELAY_PRECEDES_BACKLOG',FALSE,FALSE),
 ('HIST_2026_07',3,'WAREHOUSE','WH-WEST','ORDER','OR-H2','BACKLOG_PRECEDES_LATE_DELIVERY',FALSE,FALSE),
 ('HIST_2026_07',4,'ORDER','OR-H2','SUPPORT_TICKET','ST-H2','LATE_DELIVERY_PRECEDES_COMPLAINT',FALSE,FALSE),
 ('HIST_2026_07',5,'SUPPORT_TICKET','ST-H2','REFUND','RF-H2','COMPLAINT_ASSOCIATED_WITH_REFUND',FALSE,FALSE),
 ('HIST_2026_07',6,'REFUND','RF-H2','BUSINESS_METRIC','west:2026-07','REFUNDS_ASSOCIATED_WITH_REVENUE_IMPACT',FALSE,TRUE);
