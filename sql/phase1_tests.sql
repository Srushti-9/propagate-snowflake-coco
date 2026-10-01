-- PROPAGATE :: Phase 1 :: phase1_tests.sql
-- Validation harness. Every check returns (check_name, expected, actual, status).
-- Expectation: all rows status = 'PASS'. Final row reports overall pass count.

WITH checks AS (
  -- ---- row counts (deterministic) ----
  SELECT 'suppliers_count' c, '4' expected, (SELECT COUNT(*)::string FROM PROPAGATE.CORE.SUPPLIERS) actual
  UNION ALL SELECT 'warehouses_count','3',(SELECT COUNT(*)::string FROM PROPAGATE.CORE.WAREHOUSES)
  UNION ALL SELECT 'customers_count','8',(SELECT COUNT(*)::string FROM PROPAGATE.CORE.CUSTOMERS)
  UNION ALL SELECT 'supplier_comms_count','4',(SELECT COUNT(*)::string FROM PROPAGATE.DOCS.SUPPLIER_COMMS)
  UNION ALL SELECT 'support_tickets_count','8',(SELECT COUNT(*)::string FROM PROPAGATE.DOCS.SUPPORT_TICKETS)
  UNION ALL SELECT 'shipments_count','7',(SELECT COUNT(*)::string FROM PROPAGATE.CORE.SHIPMENTS)
  UNION ALL SELECT 'orders_count','8',(SELECT COUNT(*)::string FROM PROPAGATE.CORE.ORDERS)
  UNION ALL SELECT 'refunds_count','7',(SELECT COUNT(*)::string FROM PROPAGATE.CORE.REFUNDS)
  UNION ALL SELECT 'warehouse_daily_count','366',(SELECT COUNT(*)::string FROM PROPAGATE.CORE.WAREHOUSE_DAILY)
  UNION ALL SELECT 'business_metrics_count','366',(SELECT COUNT(*)::string FROM PROPAGATE.CORE.BUSINESS_METRICS)
  UNION ALL SELECT 'ground_truth_edges_count','18',(SELECT COUNT(*)::string FROM PROPAGATE.ANALYTICS.GROUND_TRUTH_EDGES)
  -- ---- referential integrity (expect 0 orphans) ----
  UNION ALL SELECT 'orphan_order_customer','0',(SELECT COUNT(*)::string FROM PROPAGATE.CORE.ORDERS o LEFT JOIN PROPAGATE.CORE.CUSTOMERS c USING(customer_id) WHERE c.customer_id IS NULL)
  UNION ALL SELECT 'orphan_order_warehouse','0',(SELECT COUNT(*)::string FROM PROPAGATE.CORE.ORDERS o LEFT JOIN PROPAGATE.CORE.WAREHOUSES w USING(warehouse_id) WHERE w.warehouse_id IS NULL)
  UNION ALL SELECT 'orphan_order_shipment','0',(SELECT COUNT(*)::string FROM PROPAGATE.CORE.ORDERS o LEFT JOIN PROPAGATE.CORE.SHIPMENTS s USING(shipment_id) WHERE s.shipment_id IS NULL)
  UNION ALL SELECT 'orphan_refund_order','0',(SELECT COUNT(*)::string FROM PROPAGATE.CORE.REFUNDS r LEFT JOIN PROPAGATE.CORE.ORDERS o USING(order_id) WHERE o.order_id IS NULL)
  UNION ALL SELECT 'orphan_ticket_order','0',(SELECT COUNT(*)::string FROM PROPAGATE.DOCS.SUPPORT_TICKETS t LEFT JOIN PROPAGATE.CORE.ORDERS o ON t.order_ref=o.order_id WHERE t.order_ref IS NOT NULL AND o.order_id IS NULL)
  UNION ALL SELECT 'orphan_comm_supplier','0',(SELECT COUNT(*)::string FROM PROPAGATE.DOCS.SUPPLIER_COMMS d LEFT JOIN PROPAGATE.CORE.SUPPLIERS s ON d.entity_ref=s.supplier_id WHERE s.supplier_id IS NULL)
  -- ---- golden-chain entity existence (every ground-truth source/target id resolves, except BUSINESS_METRIC label) ----
  UNION ALL SELECT 'gt_supplier_comm_ids_exist','0',(SELECT COUNT(*)::string FROM PROPAGATE.ANALYTICS.GROUND_TRUTH_EDGES g WHERE g.from_type='SUPPLIER_COMM' AND g.from_id NOT IN (SELECT doc_id FROM PROPAGATE.DOCS.SUPPLIER_COMMS))
  UNION ALL SELECT 'gt_shipment_ids_exist','0',(SELECT COUNT(*)::string FROM PROPAGATE.ANALYTICS.GROUND_TRUTH_EDGES g WHERE g.to_type='SHIPMENT' AND g.to_id NOT IN (SELECT shipment_id FROM PROPAGATE.CORE.SHIPMENTS))
  UNION ALL SELECT 'gt_order_ids_exist','0',(SELECT COUNT(*)::string FROM PROPAGATE.ANALYTICS.GROUND_TRUTH_EDGES g WHERE g.to_type='ORDER' AND g.to_id NOT IN (SELECT order_id FROM PROPAGATE.CORE.ORDERS))
  UNION ALL SELECT 'gt_ticket_ids_exist','0',(SELECT COUNT(*)::string FROM PROPAGATE.ANALYTICS.GROUND_TRUTH_EDGES g WHERE g.to_type='SUPPORT_TICKET' AND g.to_id NOT IN (SELECT doc_id FROM PROPAGATE.DOCS.SUPPORT_TICKETS))
  UNION ALL SELECT 'gt_refund_ids_exist','0',(SELECT COUNT(*)::string FROM PROPAGATE.ANALYTICS.GROUND_TRUTH_EDGES g WHERE g.to_type='REFUND' AND g.to_id NOT IN (SELECT refund_id FROM PROPAGATE.CORE.REFUNDS))
  -- ---- exactly one root + one impact per chain ----
  UNION ALL SELECT 'roots_per_chain_ok','3',(SELECT COUNT(*)::string FROM (SELECT chain_label FROM PROPAGATE.ANALYTICS.GROUND_TRUTH_EDGES WHERE is_root GROUP BY chain_label HAVING COUNT(*)=1))
  UNION ALL SELECT 'impacts_per_chain_ok','3',(SELECT COUNT(*)::string FROM (SELECT chain_label FROM PROPAGATE.ANALYTICS.GROUND_TRUTH_EDGES WHERE is_impact GROUP BY chain_label HAVING COUNT(*)=1))
  -- ---- signal present: golden WH-WEST backlog spike >> baseline ----
  UNION ALL SELECT 'golden_backlog_spike','PASS',
    (SELECT IFF(MAX(backlog_units) >= 1900, 'PASS','FAIL') FROM PROPAGATE.CORE.WAREHOUSE_DAILY WHERE warehouse_id='WH-WEST' AND date BETWEEN '2026-09-05' AND '2026-09-14')
  UNION ALL SELECT 'baseline_backlog_low','PASS',
    (SELECT IFF(MAX(backlog_units) <= 600,'PASS','FAIL') FROM PROPAGATE.CORE.WAREHOUSE_DAILY WHERE warehouse_id='WH-EAST')
  -- ---- impact present: golden west revenue dip below baseline ----
  UNION ALL SELECT 'golden_revenue_dip','PASS',
    (SELECT IFF(MIN(revenue) < 90000,'PASS','FAIL') FROM PROPAGATE.CORE.BUSINESS_METRICS WHERE region='west' AND metric_date BETWEEN '2026-09-18' AND '2026-09-25')
  -- ---- distractor present but NOT in ground truth ----
  UNION ALL SELECT 'distractor_order_exists','1',(SELECT COUNT(*)::string FROM PROPAGATE.CORE.ORDERS WHERE order_id='OR-D1')
  UNION ALL SELECT 'distractor_not_in_gt','0',(SELECT COUNT(*)::string FROM PROPAGATE.ANALYTICS.GROUND_TRUTH_EDGES WHERE from_id='OR-D1' OR to_id='OR-D1' OR from_id='SC-D1' OR to_id='SC-D1')
  UNION ALL SELECT 'east_promo_blip_exists','PASS',
    (SELECT IFF(MAX(revenue) >= 110000,'PASS','FAIL') FROM PROPAGATE.CORE.BUSINESS_METRICS WHERE region='east' AND metric_date BETWEEN '2026-09-14' AND '2026-09-18')
)
SELECT c AS check_name, expected, actual,
       IFF(expected = actual, 'PASS','FAIL') AS status
FROM checks
ORDER BY status DESC, check_name;
