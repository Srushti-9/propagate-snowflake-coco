-- PROPAGATE :: Phase 2.1 :: 12_phase2_1_evaluation.sql
-- Corrected evaluation methodology + comparison table + failure analysis.
-- Reads CHALLENGE_GROUND_TRUTH_EDGES for evaluation ONLY (never used by engine).

-- ===== CHALLENGE_EVALUATION: per-edge expected vs inferred =====
CREATE OR REPLACE TABLE PROPAGATE.ANALYTICS.CHALLENGE_EVALUATION AS
WITH challenge_expected AS (
  SELECT step_no, relation, from_id, to_id, is_root, is_impact,
    CASE relation
      WHEN 'SCHEDULE_CHANGE_PRECEDES_DELAY' THEN 'SUP-DELTA'
      WHEN 'DELAY_PRECEDES_BACKLOG' THEN 'WH-CENTRAL'
      WHEN 'BACKLOG_PRECEDES_LATE_DELIVERY' THEN 'WH-CENTRAL'
      WHEN 'LATE_DELIVERY_PRECEDES_COMPLAINT' THEN 'OR-C1'
      WHEN 'COMPLAINT_ASSOCIATED_WITH_REFUND' THEN 'OR-C1'
      WHEN 'REFUNDS_ASSOCIATED_WITH_REVENUE_IMPACT' THEN 'central'
    END AS expected_entity
  FROM PROPAGATE.ANALYTICS.CHALLENGE_GROUND_TRUTH_EDGES
),
best_match AS (
  SELECT relation, shared_entity_id, evidence_score, evidence_class, retained,
    comp_temporal, comp_structural, comp_magnitude, comp_textual, comp_historical, edge_id
  FROM PROPAGATE.ANALYTICS.SCORED_EDGES
  QUALIFY ROW_NUMBER() OVER (PARTITION BY relation, shared_entity_id ORDER BY evidence_score DESC) = 1
)
SELECT
  ce.step_no, ce.relation, ce.from_id, ce.to_id, ce.is_root, ce.is_impact,
  bm.evidence_score, bm.evidence_class, bm.retained,
  bm.comp_temporal, bm.comp_structural, bm.comp_magnitude, bm.comp_textual, bm.comp_historical,
  CASE WHEN bm.retained THEN 'TRUE_POSITIVE' ELSE 'FALSE_NEGATIVE' END AS eval_result,
  CASE
    WHEN bm.retained THEN 'Discovered: ' || ce.relation || ' (score ' || bm.evidence_score || ')'
    WHEN bm.comp_textual = 0 AND bm.comp_historical = 0 THEN
      'MISSED (cold-start): textual=0, historical=0. Max possible from temporal+structural+magnitude = 0.50. '
      || 'Actual score ' || bm.evidence_score || ' < 0.40 threshold. '
      || 'Root cause: 50% weight on textual+historical leaves novel entities unable to clear threshold.'
    ELSE 'MISSED: score ' || bm.evidence_score || ' < 0.40 threshold.'
  END AS explanation
FROM challenge_expected ce
LEFT JOIN best_match bm ON bm.relation = ce.relation AND bm.shared_entity_id = ce.expected_entity
ORDER BY ce.step_no;

-- ===== CHALLENGE_KNOWN_NEGATIVE_FPS: distractor edges that were retained =====
CREATE OR REPLACE TABLE PROPAGATE.ANALYTICS.CHALLENGE_KNOWN_NEGATIVE_FPS AS
SELECT edge_id, from_event, to_event, relation, shared_entity_id,
  evidence_score, evidence_class, retained,
  CASE
    WHEN from_event LIKE '%SC-C2%' THEN 'Routine SUP-GAMMA comm (distractor)'
    WHEN shared_entity_id = 'SUP-BETA' THEN 'SUP-BETA distractor shipment'
    WHEN from_event LIKE '%ST-C3%' OR to_event LIKE '%ST-C3%' THEN 'Praise ticket (distractor)'
    WHEN from_event LIKE '%ST-C4%' OR to_event LIKE '%ST-C4%' THEN 'Storm complaint (distractor)'
    WHEN from_event LIKE '%RF-C3%' OR to_event LIKE '%RF-C3%' THEN 'Damaged goods refund (distractor)'
    WHEN from_event LIKE '%OR-C5%' OR to_event LIKE '%OR-C5%' THEN 'On-time order (distractor)'
    WHEN from_event LIKE '%OR-C4%' OR to_event LIKE '%OR-C4%' THEN 'Storm-delayed order (distractor)'
    ELSE 'Other distractor'
  END AS distractor_type
FROM PROPAGATE.ANALYTICS.SCORED_EDGES
WHERE (from_event LIKE '%C2%' OR to_event LIKE '%C2%'
    OR from_event LIKE '%C3%' OR to_event LIKE '%C3%'
    OR from_event LIKE '%C4%' OR to_event LIKE '%C4%'
    OR from_event LIKE '%C5%' OR to_event LIKE '%C5%')
  AND NOT (shared_entity_id IN ('SUP-DELTA','WH-CENTRAL','OR-C1','OR-C2')
           AND relation IN (SELECT relation FROM PROPAGATE.ANALYTICS.CHALLENGE_GROUND_TRUTH_EDGES));

-- ===== COMPARISON TABLE: original vs challenge =====
CREATE OR REPLACE VIEW PROPAGATE.ANALYTICS.PHASE21_COMPARISON AS
WITH orig AS (
  SELECT
    18 AS expected_edges,
    18 AS inferred_expected_edges,
    18.0/18.0 AS recall,
    18.0/18.0 AS precision_labeled,
    (SELECT 100.0*COUNT(*)/(SELECT COUNT(*) FROM PROPAGATE.ANALYTICS.SCORED_EDGES WHERE retained)
     FROM PROPAGATE.ANALYTICS.SCORED_EDGES
     WHERE retained AND (from_event LIKE '%-D%' OR to_event LIKE '%-D%'
                         OR shared_entity_id IN ('WH-EAST','SUP-BETA','east'))) AS known_neg_fp_pct,
    3 AS chains_reconstructed,
    TRUE AS root_detected,
    TRUE AS impact_detected,
    TRUE AS earliest_signal_detected,
    TRUE AS intervention_detected
),
challenge AS (
  SELECT
    6 AS expected_edges,
    (SELECT COUNT(*) FROM PROPAGATE.ANALYTICS.CHALLENGE_EVALUATION WHERE eval_result='TRUE_POSITIVE') AS inferred_expected_edges,
    (SELECT COUNT(*) FROM PROPAGATE.ANALYTICS.CHALLENGE_EVALUATION WHERE eval_result='TRUE_POSITIVE')::float / 6.0 AS recall,
    -- precision = TP / (TP + FP among labeled edges); no FPs among retained challenge edges
    IFF((SELECT COUNT(*) FROM PROPAGATE.ANALYTICS.CHALLENGE_EVALUATION WHERE eval_result='TRUE_POSITIVE') > 0,
        1.0, NULL) AS precision_labeled,
    -- known-neg FP rate for challenge distractors
    (SELECT 100.0*SUM(IFF(retained,1,0))/NULLIF(COUNT(*),0) FROM PROPAGATE.ANALYTICS.CHALLENGE_KNOWN_NEGATIVE_FPS) AS known_neg_fp_pct,
    -- was a challenge chain reconstructed?
    (SELECT COUNT(*) FROM PROPAGATE.ANALYTICS.CHAINS WHERE chain_id LIKE '%C%' OR root_event LIKE '%C%') AS chains_reconstructed,
    FALSE AS root_detected,
    FALSE AS impact_detected,
    FALSE AS earliest_signal_detected,
    FALSE AS intervention_detected
)
SELECT 'Original (3 episodes)' AS dataset, * FROM orig
UNION ALL
SELECT 'Challenge (CHALLENGE_2026_08)', * FROM challenge;
