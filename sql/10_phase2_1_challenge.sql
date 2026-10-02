-- PROPAGATE :: Phase 2.1 :: 10_phase2_1_challenge.sql
-- Generalization challenge: inject CHALLENGE_2026_08 episode using entities
-- never used in existing chains (SUP-DELTA, WH-CENTRAL, central region).
-- All values are deterministic (no RNG). Re-runnable: uses INSERT only (additive).
-- IMPORTANT: This file does NOT modify any engine logic.

-- ===================== CHALLENGE EPISODE: SUPPLIER COMMS =====================
-- SC-C1: disruption comm (different wording from golden)
-- SC-C2: distractor — routine comm from SUP-GAMMA
INSERT INTO PROPAGATE.DOCS.SUPPLIER_COMMS (doc_id, entity_ref, warehouse_ref, event_time, body_text) VALUES
 ('SC-C1','SUP-DELTA','WH-CENTRAL','2026-08-03 10:00',
  'Critical update: a production line failure at our central facility will delay all outbound shipments to WH-CENTRAL by approximately one week. We are working to restore capacity but expect continued disruption through mid-August.'),
 ('SC-C2','SUP-GAMMA','WH-WEST','2026-08-04 09:00',
  'Monthly status report: all shipments to WH-WEST are proceeding normally this cycle. No delays or changes to the delivery schedule are expected.');

-- ===================== CHALLENGE EPISODE: SHIPMENTS =====================
-- SH-C1, SH-C2: delayed shipments from SUP-DELTA to WH-CENTRAL
-- SH-C3: distractor — minor SUP-BETA delay to WH-EAST
INSERT INTO PROPAGATE.CORE.SHIPMENTS VALUES
 ('SH-C1','SUP-DELTA','SUP-HUB-C','WH-CENTRAL','2026-08-07','2026-08-14',7,'LATE'),
 ('SH-C2','SUP-DELTA','SUP-HUB-C','WH-CENTRAL','2026-08-08','2026-08-16',8,'LATE'),
 ('SH-C3','SUP-BETA','SUP-HUB-E','WH-EAST','2026-08-08','2026-08-11',3,'LATE');

-- ===================== CHALLENGE EPISODE: ORDERS =====================
-- OR-C1, OR-C2, OR-C3: late orders from WH-CENTRAL
-- OR-C4: distractor — late order from WH-EAST (different cause: storm)
-- OR-C5: distractor — on-time order from WH-EAST
INSERT INTO PROPAGATE.CORE.ORDERS VALUES
 ('OR-C1','CUST-107','WH-CENTRAL','SH-C1','2026-08-06','2026-08-13','2026-08-17',TRUE),
 ('OR-C2','CUST-108','WH-CENTRAL','SH-C2','2026-08-06','2026-08-13','2026-08-18',TRUE),
 ('OR-C3','CUST-107','WH-CENTRAL','SH-C1','2026-08-07','2026-08-14','2026-08-18',TRUE),
 ('OR-C4','CUST-105','WH-EAST','SH-C3','2026-08-07','2026-08-12','2026-08-14',TRUE),
 ('OR-C5','CUST-106','WH-EAST','SH-C3','2026-08-08','2026-08-15','2026-08-14',FALSE);

-- ===================== CHALLENGE EPISODE: SUPPORT TICKETS =====================
-- ST-C1, ST-C2: complaints about late delivery (different wording)
-- ST-C3: distractor — praise ticket
-- ST-C4: distractor — storm-related complaint (different cause)
INSERT INTO PROPAGATE.DOCS.SUPPORT_TICKETS (doc_id, entity_ref, order_ref, event_time, body_text) VALUES
 ('ST-C1','CUST-107','OR-C1','2026-08-19 10:00',
  'Our order was supposed to arrive last week but it is almost a week overdue. This delay has impacted our operations significantly. Requesting immediate resolution and a full refund.'),
 ('ST-C2','CUST-108','OR-C2','2026-08-20 14:00',
  'The shipment is unacceptably late. We have been waiting over a week past the promised delivery date. We need a complete refund for this order.'),
 ('ST-C3','CUST-105',NULL,'2026-08-17 11:00',
  'Excellent turnaround on our recent order. Impressed with the service quality this month.'),
 ('ST-C4','CUST-106','OR-C4','2026-08-16 13:00',
  'Order arrived a couple days late, I think there was some weather disruption in the area. Not a major issue but wanted to flag it.');

-- ===================== CHALLENGE EPISODE: REFUNDS =====================
-- RF-C1, RF-C2: late delivery refunds
-- RF-C3: distractor — damaged goods refund (unrelated reason)
INSERT INTO PROPAGATE.CORE.REFUNDS VALUES
 ('RF-C1','OR-C1','2026-08-22',1400.00,'LATE_DELIVERY'),
 ('RF-C2','OR-C2','2026-08-23',800.00,'LATE_DELIVERY'),
 ('RF-C3','OR-C5','2026-08-20',250.00,'DAMAGED');

-- ===================== WAREHOUSE DAILY: WH-CENTRAL backlog spike =====================
-- Weaker than golden (800-900 vs golden's 1900-2080), but still statistically detectable.
UPDATE PROPAGATE.CORE.WAREHOUSE_DAILY
   SET backlog_units = 800 + 40*MOD(DATEDIFF('day','2026-08-12',date),8),
       utilization_pct = ROUND(100.0*(800 + 40*MOD(DATEDIFF('day','2026-08-12',date),8))/9000, 2)
 WHERE warehouse_id='WH-CENTRAL' AND date BETWEEN '2026-08-12' AND '2026-08-19';

-- ===================== BUSINESS METRICS: central revenue dip =====================
UPDATE PROPAGATE.CORE.BUSINESS_METRICS
   SET revenue = 78000 + MOD(DATEDIFF('day','2026-08-26',metric_date),3)*1200,
       repeat_purchase_rate = 0.48, support_ticket_count = 20
 WHERE region='central' AND metric_date BETWEEN '2026-08-26' AND '2026-08-31';

-- Small east fluctuation (distractor — should NOT be interpreted as chain impact)
UPDATE PROPAGATE.CORE.BUSINESS_METRICS
   SET revenue = 105000, support_ticket_count = 6
 WHERE region='east' AND metric_date BETWEEN '2026-08-15' AND '2026-08-17';

-- ===================== CHALLENGE GROUND TRUTH (evaluation only) =====================
-- CRITICAL: This table is NEVER read by the engine (04-07 scripts).
-- It is used ONLY by the evaluation step (12_phase2_1_evaluation.sql).
CREATE OR REPLACE TABLE PROPAGATE.ANALYTICS.CHALLENGE_GROUND_TRUTH_EDGES (
  chain_label STRING, step_no NUMBER,
  from_type STRING, from_id STRING,
  to_type STRING, to_id STRING,
  relation STRING, is_root BOOLEAN, is_impact BOOLEAN
);

INSERT INTO PROPAGATE.ANALYTICS.CHALLENGE_GROUND_TRUTH_EDGES VALUES
 ('CHALLENGE_2026_08',1,'SUPPLIER_COMM','SC-C1','SHIPMENT','SH-C1','SCHEDULE_CHANGE_PRECEDES_DELAY',TRUE,FALSE),
 ('CHALLENGE_2026_08',2,'SHIPMENT','SH-C1','WAREHOUSE','WH-CENTRAL','DELAY_PRECEDES_BACKLOG',FALSE,FALSE),
 ('CHALLENGE_2026_08',3,'WAREHOUSE','WH-CENTRAL','ORDER','OR-C1','BACKLOG_PRECEDES_LATE_DELIVERY',FALSE,FALSE),
 ('CHALLENGE_2026_08',4,'ORDER','OR-C1','SUPPORT_TICKET','ST-C1','LATE_DELIVERY_PRECEDES_COMPLAINT',FALSE,FALSE),
 ('CHALLENGE_2026_08',5,'SUPPORT_TICKET','ST-C1','REFUND','RF-C1','COMPLAINT_ASSOCIATED_WITH_REFUND',FALSE,FALSE),
 ('CHALLENGE_2026_08',6,'REFUND','RF-C1','BUSINESS_METRIC','central:2026-08','REFUNDS_ASSOCIATED_WITH_REVENUE_IMPACT',FALSE,TRUE);
