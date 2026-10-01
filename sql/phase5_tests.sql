-- PROPAGATE :: Phase 5 :: phase5_tests.sql
-- Validates chain reconstruction, earliest-signal detection, intervention, and no distractor leakage.

WITH gce AS (SELECT * FROM PROPAGATE.ANALYTICS.CHAIN_EDGES WHERE chain_id='CHAIN_SC-G1'),
golden_rel AS (
  SELECT LISTAGG(relation, '|') WITHIN GROUP (ORDER BY step_no) AS rel_seq,
         COUNT(*) AS edge_count,
         COUNT(DISTINCT relation) AS distinct_rel,
         SUM(IFF(from_event LIKE '%-D%' OR to_event LIKE '%-D%' OR from_event LIKE '%-H%' OR to_event LIKE '%-H%',1,0)) AS fp_edges
  FROM gce
),
checks AS (
  SELECT 'chains_count' c, '3' expected, (SELECT COUNT(*)::string FROM PROPAGATE.ANALYTICS.CHAINS) actual
  UNION ALL SELECT 'golden_root','EVT_SC_SC-G1',(SELECT root_event FROM PROPAGATE.ANALYTICS.CHAINS WHERE chain_id='CHAIN_SC-G1')
  UNION ALL SELECT 'golden_impact_region','west',(SELECT impact_region FROM PROPAGATE.ANALYTICS.CHAINS WHERE chain_id='CHAIN_SC-G1')
  UNION ALL SELECT 'golden_node_count','7',(SELECT node_count::string FROM PROPAGATE.ANALYTICS.CHAINS WHERE chain_id='CHAIN_SC-G1')
  UNION ALL SELECT 'golden_edge_count','6',(SELECT edge_count::string FROM golden_rel)
  UNION ALL SELECT 'golden_relations_complete','6',(SELECT distinct_rel::string FROM golden_rel)
  UNION ALL SELECT 'golden_steps_in_order','SCHEDULE_CHANGE_PRECEDES_DELAY|DELAY_PRECEDES_BACKLOG|BACKLOG_PRECEDES_LATE_DELIVERY|LATE_DELIVERY_PRECEDES_COMPLAINT|COMPLAINT_ASSOCIATED_WITH_REFUND|REFUNDS_ASSOCIATED_WITH_REVENUE_IMPACT',(SELECT rel_seq FROM golden_rel)
  -- reconstruction F1 (precision & recall = 1 => F1 = 1): 0 false edges, all 6 relations covered
  UNION ALL SELECT 'golden_false_edges','0',(SELECT fp_edges::string FROM golden_rel)
  -- earliest-signal hit vs ground truth (root matches GROUND_TRUTH is_root)
  UNION ALL SELECT 'golden_earliest_signal_hit','PASS',
    (SELECT IFF((SELECT root_event FROM PROPAGATE.ANALYTICS.CHAINS WHERE chain_id='CHAIN_SC-G1')
              = 'EVT_SC_'||(SELECT from_id FROM PROPAGATE.ANALYTICS.GROUND_TRUTH_EDGES WHERE chain_label='GOLDEN_2026_09' AND is_root),'PASS','FAIL'))
  UNION ALL SELECT 'hist06_earliest_signal_hit','EVT_SC_SC-H1',(SELECT root_event FROM PROPAGATE.ANALYTICS.CHAINS WHERE chain_id='CHAIN_SC-H1')
  UNION ALL SELECT 'hist07_earliest_signal_hit','EVT_SC_SC-H2',(SELECT root_event FROM PROPAGATE.ANALYTICS.CHAINS WHERE chain_id='CHAIN_SC-H2')
  -- all chains fully supported (no correlation-only edge)
  UNION ALL SELECT 'all_chains_supported','3',(SELECT COUNT(*)::string FROM PROPAGATE.ANALYTICS.CHAINS WHERE all_edges_supported)
  UNION ALL SELECT 'no_correlation_only_in_chains','0',(SELECT COUNT(*)::string FROM PROPAGATE.ANALYTICS.CHAIN_EDGES WHERE evidence_class='CORRELATION_ONLY')
  -- no distractor events anywhere in chains
  UNION ALL SELECT 'no_distractor_in_chains','0',(SELECT COUNT(*)::string FROM PROPAGATE.ANALYTICS.CHAIN_EDGES WHERE from_event LIKE '%-D%' OR to_event LIKE '%-D%' OR from_event LIKE '%EAST%' OR to_event LIKE '%_east_%')
  -- every chain edge is a retained scored edge
  UNION ALL SELECT 'chain_edges_retained','0',(SELECT COUNT(*)::string FROM PROPAGATE.ANALYTICS.CHAIN_EDGES ce LEFT JOIN PROPAGATE.ANALYTICS.SCORED_EDGES se ON se.edge_id=ce.edge_id AND se.retained WHERE se.edge_id IS NULL)
  -- intervention defined and plausible
  UNION ALL SELECT 'golden_intervention_function','SUPPLIER',(SELECT intervention_function FROM PROPAGATE.ANALYTICS.CHAINS WHERE chain_id='CHAIN_SC-G1')
  UNION ALL SELECT 'golden_intervention_lead_positive','PASS',(SELECT IFF(intervention_lead_days > 0,'PASS','FAIL') FROM PROPAGATE.ANALYTICS.CHAINS WHERE chain_id='CHAIN_SC-G1')
)
SELECT c AS check_name, expected, actual, IFF(expected = actual,'PASS','FAIL') AS status
FROM checks ORDER BY status DESC, check_name;
