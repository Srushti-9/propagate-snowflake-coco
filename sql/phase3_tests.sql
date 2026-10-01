-- PROPAGATE :: Phase 3 :: phase3_tests.sql
-- Validates candidate linking. Key metric: RECALL of true chain steps (each true step has >=1 candidate).
-- Distractors are allowed to appear here; precision is handled by evidence scoring in Phase 4.

WITH ce AS (SELECT * FROM PROPAGATE.ANALYTICS.CANDIDATE_EDGES),
rec AS (  -- recall per chain: 1 if the step has >=1 candidate edge
  SELECT
    -- GOLDEN
    IFF(EXISTS(SELECT 1 FROM ce WHERE from_event='EVT_SC_SC-G1' AND to_event='EVT_SH_SH-G1'),1,0)
   +IFF(EXISTS(SELECT 1 FROM ce WHERE from_event='EVT_SH_SH-G1' AND to_type='WAREHOUSE_BACKLOG' AND shared_entity_id='WH-WEST'),1,0)
   +IFF(EXISTS(SELECT 1 FROM ce WHERE from_type='WAREHOUSE_BACKLOG' AND shared_entity_id='WH-WEST' AND to_event='EVT_OR_OR-G1'),1,0)
   +IFF(EXISTS(SELECT 1 FROM ce WHERE from_event='EVT_OR_OR-G1' AND to_event='EVT_ST_ST-G1'),1,0)
   +IFF(EXISTS(SELECT 1 FROM ce WHERE from_event='EVT_ST_ST-G1' AND to_event='EVT_RF_RF-G1'),1,0)
   +IFF(EXISTS(SELECT 1 FROM ce WHERE from_event='EVT_RF_RF-G1' AND to_type='REVENUE' AND shared_entity_id='west'),1,0) AS golden_recall,
    -- HIST 2026_06
    IFF(EXISTS(SELECT 1 FROM ce WHERE from_event='EVT_SC_SC-H1' AND to_event='EVT_SH_SH-H1'),1,0)
   +IFF(EXISTS(SELECT 1 FROM ce WHERE from_event='EVT_SH_SH-H1' AND to_type='WAREHOUSE_BACKLOG' AND shared_entity_id='WH-WEST'),1,0)
   +IFF(EXISTS(SELECT 1 FROM ce WHERE from_type='WAREHOUSE_BACKLOG' AND shared_entity_id='WH-WEST' AND to_event='EVT_OR_OR-H1'),1,0)
   +IFF(EXISTS(SELECT 1 FROM ce WHERE from_event='EVT_OR_OR-H1' AND to_event='EVT_ST_ST-H1'),1,0)
   +IFF(EXISTS(SELECT 1 FROM ce WHERE from_event='EVT_ST_ST-H1' AND to_event='EVT_RF_RF-H1'),1,0)
   +IFF(EXISTS(SELECT 1 FROM ce WHERE from_event='EVT_RF_RF-H1' AND to_type='REVENUE' AND shared_entity_id='west'),1,0) AS hist06_recall,
    -- HIST 2026_07
    IFF(EXISTS(SELECT 1 FROM ce WHERE from_event='EVT_SC_SC-H2' AND to_event='EVT_SH_SH-H2'),1,0)
   +IFF(EXISTS(SELECT 1 FROM ce WHERE from_event='EVT_SH_SH-H2' AND to_type='WAREHOUSE_BACKLOG' AND shared_entity_id='WH-WEST'),1,0)
   +IFF(EXISTS(SELECT 1 FROM ce WHERE from_type='WAREHOUSE_BACKLOG' AND shared_entity_id='WH-WEST' AND to_event='EVT_OR_OR-H2'),1,0)
   +IFF(EXISTS(SELECT 1 FROM ce WHERE from_event='EVT_OR_OR-H2' AND to_event='EVT_ST_ST-H2'),1,0)
   +IFF(EXISTS(SELECT 1 FROM ce WHERE from_event='EVT_ST_ST-H2' AND to_event='EVT_RF_RF-H2'),1,0)
   +IFF(EXISTS(SELECT 1 FROM ce WHERE from_event='EVT_RF_RF-H2' AND to_type='REVENUE' AND shared_entity_id='west'),1,0) AS hist07_recall
),
checks AS (
  SELECT 'golden_recall' c, '6' expected, (SELECT golden_recall::string FROM rec) actual
  UNION ALL SELECT 'hist06_recall','6',(SELECT hist06_recall::string FROM rec)
  UNION ALL SELECT 'hist07_recall','6',(SELECT hist07_recall::string FROM rec)
  -- precedence integrity: no backward/zero-negative edges
  UNION ALL SELECT 'no_backward_edges','0',(SELECT COUNT(*)::string FROM ce WHERE lag_days < 0)
  -- lag-window compliance against config
  UNION ALL SELECT 'lag_window_violations','0',(SELECT COUNT(*)::string FROM ce JOIN PROPAGATE.ANALYTICS.LAG_WINDOWS l ON ce.relation=l.relation WHERE ce.lag_days > l.max_lag_days)
  -- no self loops
  UNION ALL SELECT 'no_self_loops','0',(SELECT COUNT(*)::string FROM ce WHERE from_event = to_event)
  -- unknown relations (every edge relation exists in config)
  UNION ALL SELECT 'unknown_relations','0',(SELECT COUNT(*)::string FROM ce WHERE relation NOT IN (SELECT relation FROM PROPAGATE.ANALYTICS.LAG_WINDOWS))
  -- sanity: candidates were generated
  UNION ALL SELECT 'has_candidates','PASS',(SELECT IFF(COUNT(*) BETWEEN 50 AND 1000,'PASS','FAIL') FROM ce)
  -- distractor edge DID enter candidates (shows permissive linking) but is NOT ground truth
  UNION ALL SELECT 'distractor_candidate_present','PASS',(SELECT IFF(EXISTS(SELECT 1 FROM ce WHERE from_event='EVT_SC_SC-D1'),'PASS','FAIL'))
)
SELECT c AS check_name, expected, actual, IFF(expected = actual,'PASS','FAIL') AS status
FROM checks ORDER BY status DESC, check_name;
