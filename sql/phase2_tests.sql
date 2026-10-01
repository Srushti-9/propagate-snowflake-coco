-- PROPAGATE :: Phase 2 :: phase2_tests.sql
-- Validates the event spine. Expectation: all rows status = 'PASS'.

WITH g AS (  -- golden-chain key timestamps
  SELECT
    (SELECT event_time FROM PROPAGATE.ANALYTICS.EVENT_LOG WHERE event_id='EVT_SC_SC-G1') t_comm,
    (SELECT MIN(event_time) FROM PROPAGATE.ANALYTICS.EVENT_LOG WHERE event_id IN ('EVT_SH_SH-G1','EVT_SH_SH-G2','EVT_SH_SH-G3')) t_ship,
    (SELECT MIN(event_time) FROM PROPAGATE.ANALYTICS.EVENT_LOG WHERE event_type='WAREHOUSE_BACKLOG' AND link_warehouse_id='WH-WEST' AND event_time BETWEEN '2026-09-05' AND '2026-09-14') t_backlog,
    (SELECT MIN(event_time) FROM PROPAGATE.ANALYTICS.EVENT_LOG WHERE event_id IN ('EVT_OR_OR-G1','EVT_OR_OR-G2','EVT_OR_OR-G3','EVT_OR_OR-G4')) t_order,
    (SELECT MIN(event_time) FROM PROPAGATE.ANALYTICS.EVENT_LOG WHERE event_id IN ('EVT_ST_ST-G1','EVT_ST_ST-G2','EVT_ST_ST-G3','EVT_ST_ST-G4')) t_ticket,
    (SELECT MIN(event_time) FROM PROPAGATE.ANALYTICS.EVENT_LOG WHERE event_id IN ('EVT_RF_RF-G1','EVT_RF_RF-G2','EVT_RF_RF-G3','EVT_RF_RF-G4')) t_refund,
    (SELECT MIN(event_time) FROM PROPAGATE.ANALYTICS.EVENT_LOG WHERE event_type='REVENUE' AND link_region='west' AND event_time BETWEEN '2026-09-18' AND '2026-09-25') t_rev
),
checks AS (
  SELECT 'eventlog_total' c, '766' expected, (SELECT COUNT(*)::string FROM PROPAGATE.ANALYTICS.EVENT_LOG) actual
  UNION ALL SELECT 'cnt_schedule_change','4',(SELECT COUNT(*)::string FROM PROPAGATE.ANALYTICS.EVENT_LOG WHERE event_type='SCHEDULE_CHANGE')
  UNION ALL SELECT 'cnt_shipment_delay','7',(SELECT COUNT(*)::string FROM PROPAGATE.ANALYTICS.EVENT_LOG WHERE event_type='SHIPMENT_DELAY')
  UNION ALL SELECT 'cnt_warehouse_backlog','366',(SELECT COUNT(*)::string FROM PROPAGATE.ANALYTICS.EVENT_LOG WHERE event_type='WAREHOUSE_BACKLOG')
  UNION ALL SELECT 'cnt_order_delivery','8',(SELECT COUNT(*)::string FROM PROPAGATE.ANALYTICS.EVENT_LOG WHERE event_type='ORDER_DELIVERY')
  UNION ALL SELECT 'cnt_support_ticket','8',(SELECT COUNT(*)::string FROM PROPAGATE.ANALYTICS.EVENT_LOG WHERE event_type='SUPPORT_TICKET')
  UNION ALL SELECT 'cnt_refund','7',(SELECT COUNT(*)::string FROM PROPAGATE.ANALYTICS.EVENT_LOG WHERE event_type='REFUND')
  UNION ALL SELECT 'cnt_revenue','366',(SELECT COUNT(*)::string FROM PROPAGATE.ANALYTICS.EVENT_LOG WHERE event_type='REVENUE')
  -- uniqueness + completeness
  UNION ALL SELECT 'event_id_unique','766',(SELECT COUNT(DISTINCT event_id)::string FROM PROPAGATE.ANALYTICS.EVENT_LOG)
  UNION ALL SELECT 'no_null_event_time','0',(SELECT COUNT(*)::string FROM PROPAGATE.ANALYTICS.EVENT_LOG WHERE event_time IS NULL)
  -- deviation design: numeric types non-null, doc types null
  UNION ALL SELECT 'numeric_dev_present','0',(SELECT COUNT(*)::string FROM PROPAGATE.ANALYTICS.EVENT_LOG WHERE event_type IN ('SHIPMENT_DELAY','WAREHOUSE_BACKLOG','ORDER_DELIVERY','REFUND','REVENUE') AND deviation_score IS NULL)
  UNION ALL SELECT 'doc_dev_null','0',(SELECT COUNT(*)::string FROM PROPAGATE.ANALYTICS.EVENT_LOG WHERE event_type IN ('SCHEDULE_CHANGE','SUPPORT_TICKET') AND deviation_score IS NOT NULL)
  -- signal strength
  UNION ALL SELECT 'golden_backlog_dev_strong','PASS',(SELECT IFF(MAX(deviation_score) >= 2.5,'PASS','FAIL') FROM PROPAGATE.ANALYTICS.EVENT_LOG WHERE event_type='WAREHOUSE_BACKLOG' AND link_warehouse_id='WH-WEST' AND event_time BETWEEN '2026-09-05' AND '2026-09-14')
  UNION ALL SELECT 'east_backlog_dev_modest','PASS',(SELECT IFF(MAX(deviation_score) < 2.0,'PASS','FAIL') FROM PROPAGATE.ANALYTICS.EVENT_LOG WHERE event_type='WAREHOUSE_BACKLOG' AND link_warehouse_id='WH-EAST')
  UNION ALL SELECT 'golden_revenue_dip_strong','PASS',(SELECT IFF(MIN(deviation_score) <= -2.0,'PASS','FAIL') FROM PROPAGATE.ANALYTICS.EVENT_LOG WHERE event_type='REVENUE' AND link_region='west' AND event_time BETWEEN '2026-09-18' AND '2026-09-25')
  -- golden chain events all materialized
  UNION ALL SELECT 'golden_events_present','7',(SELECT COUNT(*)::string FROM PROPAGATE.ANALYTICS.EVENT_LOG WHERE event_id IN ('EVT_SC_SC-G1','EVT_SH_SH-G1','EVT_OR_OR-G1','EVT_ST_ST-G1','EVT_RF_RF-G1') OR (event_type='WAREHOUSE_BACKLOG' AND link_warehouse_id='WH-WEST' AND event_time='2026-09-05') OR (event_type='REVENUE' AND link_region='west' AND event_time='2026-09-18'))
  -- link denormalization worked (ticket carries order/warehouse/region)
  UNION ALL SELECT 'ticket_link_order','OR-G1',(SELECT link_order_id FROM PROPAGATE.ANALYTICS.EVENT_LOG WHERE event_id='EVT_ST_ST-G1')
  UNION ALL SELECT 'ticket_link_warehouse','WH-WEST',(SELECT link_warehouse_id FROM PROPAGATE.ANALYTICS.EVENT_LOG WHERE event_id='EVT_ST_ST-G1')
  UNION ALL SELECT 'ticket_link_region','west',(SELECT link_region FROM PROPAGATE.ANALYTICS.EVENT_LOG WHERE event_id='EVT_ST_ST-G1')
  -- temporal ordering of the golden chain (comm < ship < backlog < order < ticket < refund < revenue)
  UNION ALL SELECT 'golden_temporal_order','PASS',
    (SELECT IFF(t_comm < t_ship AND t_ship <= t_backlog AND t_backlog < t_order AND t_order <= t_ticket AND t_ticket < t_refund AND t_refund < t_rev,'PASS','FAIL') FROM g)
)
SELECT c AS check_name, expected, actual, IFF(expected = actual,'PASS','FAIL') AS status
FROM checks ORDER BY status DESC, check_name;
