-- PROPAGATE :: Phase 4 :: phase4_tests.sql
-- Validates evidence scoring, class assignment, and distractor pruning.

WITH se AS (SELECT * FROM PROPAGATE.ANALYTICS.SCORED_EDGES),
gret AS (  -- golden steps that have >=1 RETAINED edge
  SELECT
    IFF(EXISTS(SELECT 1 FROM se WHERE from_event='EVT_SC_SC-G1' AND to_event='EVT_SH_SH-G1' AND retained),1,0)
   +IFF(EXISTS(SELECT 1 FROM se WHERE from_event='EVT_SH_SH-G1' AND to_type='WAREHOUSE_BACKLOG' AND shared_entity_id='WH-WEST' AND retained),1,0)
   +IFF(EXISTS(SELECT 1 FROM se WHERE from_type='WAREHOUSE_BACKLOG' AND shared_entity_id='WH-WEST' AND to_event='EVT_OR_OR-G1' AND retained),1,0)
   +IFF(EXISTS(SELECT 1 FROM se WHERE from_event='EVT_OR_OR-G1' AND to_event='EVT_ST_ST-G1' AND retained),1,0)
   +IFF(EXISTS(SELECT 1 FROM se WHERE from_event='EVT_ST_ST-G1' AND to_event='EVT_RF_RF-G1' AND retained),1,0)
   +IFF(EXISTS(SELECT 1 FROM se WHERE from_event='EVT_RF_RF-G1' AND to_type='REVENUE' AND shared_entity_id='west' AND retained),1,0) AS n
),
checks AS (
  -- every candidate scored
  SELECT 'all_candidates_scored' c, (SELECT COUNT(*)::string FROM PROPAGATE.ANALYTICS.CANDIDATE_EDGES) expected, (SELECT COUNT(*)::string FROM se) actual
  -- components + score within [0,1]
  UNION ALL SELECT 'components_in_range','0',(SELECT COUNT(*)::string FROM se WHERE comp_temporal NOT BETWEEN 0 AND 1 OR comp_structural NOT BETWEEN 0 AND 1 OR comp_magnitude NOT BETWEEN 0 AND 1 OR comp_textual NOT BETWEEN 0 AND 1 OR comp_historical NOT BETWEEN 0 AND 1)
  UNION ALL SELECT 'score_in_range','0',(SELECT COUNT(*)::string FROM se WHERE evidence_score NOT BETWEEN 0 AND 1)
  -- golden chain fully retained after scoring
  UNION ALL SELECT 'golden_retained_steps','6',(SELECT n::string FROM gret)
  -- causality discipline
  UNION ALL SELECT 'golden_step1_is_causal','CAUSAL_STATED',(SELECT evidence_class FROM se WHERE from_event='EVT_SC_SC-G1' AND to_event='EVT_SH_SH-G1')
  UNION ALL SELECT 'causal_only_from_asserted_comms','0',(SELECT COUNT(*)::string FROM se WHERE evidence_class='CAUSAL_STATED' AND from_event NOT IN ('EVT_SC_SC-G1','EVT_SC_SC-H1','EVT_SC_SC-H2'))
  UNION ALL SELECT 'onschedule_comm_not_causal','0',(SELECT COUNT(*)::string FROM se WHERE from_event='EVT_SC_SC-D1' AND evidence_class='CAUSAL_STATED')
  -- distractor pruning
  UNION ALL SELECT 'onschedule_comm_dropped','0',(SELECT COUNT(*)::string FROM se WHERE from_event='EVT_SC_SC-D1' AND retained)
  UNION ALL SELECT 'temporal_structural_all_pruned','0',(SELECT COUNT(*)::string FROM se WHERE evidence_class='TEMPORAL_STRUCTURAL' AND retained)
  UNION ALL SELECT 'no_correlation_only_retained','0',(SELECT COUNT(*)::string FROM se WHERE evidence_class='CORRELATION_ONLY' AND retained)
  -- pruning actually happened (retained < candidates)
  UNION ALL SELECT 'pruning_occurred','PASS',(SELECT IFF((SELECT COUNT(*) FROM se WHERE retained) < (SELECT COUNT(*) FROM se),'PASS','FAIL'))
  -- class coverage: all meaningful classes present
  UNION ALL SELECT 'class_causal_present','PASS',(SELECT IFF(COUNT(*)>0,'PASS','FAIL') FROM se WHERE evidence_class='CAUSAL_STATED')
  UNION ALL SELECT 'class_text_present','PASS',(SELECT IFF(COUNT(*)>0,'PASS','FAIL') FROM se WHERE evidence_class='TEXT_SUPPORTED')
  UNION ALL SELECT 'class_historical_present','PASS',(SELECT IFF(COUNT(*)>0,'PASS','FAIL') FROM se WHERE evidence_class='HISTORICAL_SUPPORTED')
  -- historical component discriminates golden vs on-schedule distractor
  UNION ALL SELECT 'historical_discriminates','PASS',
    (SELECT IFF((SELECT MAX(comp_historical) FROM se WHERE from_event='EVT_SC_SC-G1') >= 0.5
             AND (SELECT COALESCE(MAX(comp_historical),0) FROM se WHERE from_event='EVT_SC_SC-D1') = 0,'PASS','FAIL'))
)
SELECT c AS check_name, expected, actual, IFF(expected = actual,'PASS','FAIL') AS status
FROM checks ORDER BY status DESC, check_name;
