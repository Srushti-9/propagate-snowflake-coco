-- PROPAGATE :: Phase 8 :: phase8_tests.sql
-- Asserts the validation scorecard (ANALYTICS.VALIDATION_METRICS) meets target thresholds.
-- All metrics are measurable because the Phase 1 generator injects ground-truth chains + distractors.
-- Pattern: UNION ALL of (check_name, expected, actual) -> IFF(expected=actual) PASS/FAIL.

WITH m AS (SELECT metric, value FROM PROPAGATE.ANALYTICS.VALIDATION_METRICS),
checks AS (
  -- scorecard is fully populated
  SELECT 'metrics_row_count' c, '10' expected, (SELECT COUNT(*)::string FROM m) actual
  -- reconstruction quality: precision = recall = F1 = 1.0
  UNION ALL SELECT 'f1_at_target', 'PASS',
    (SELECT IFF(value >= 0.95,'PASS','FAIL') FROM m WHERE metric='chain_reconstruction_f1')
  UNION ALL SELECT 'precision_perfect', 'PASS',
    (SELECT IFF(value = 1,'PASS','FAIL') FROM m WHERE metric='chain_reconstruction_precision')
  UNION ALL SELECT 'recall_perfect', 'PASS',
    (SELECT IFF(value = 1,'PASS','FAIL') FROM m WHERE metric='chain_reconstruction_recall')
  -- all three injected chains reconstructed
  UNION ALL SELECT 'chains_reconstructed', '3',
    (SELECT value::int::string FROM m WHERE metric='chains_reconstructed')
  -- earliest-signal detection: every chain rooted at the true early signal
  UNION ALL SELECT 'earliest_signal_detection', 'PASS',
    (SELECT IFF(value = 1,'PASS','FAIL') FROM m WHERE metric='earliest_signal_detection')
  -- evidence discipline: coverage high, correlation-only not retained in chains
  UNION ALL SELECT 'evidence_coverage_at_target', 'PASS',
    (SELECT IFF(value >= 80,'PASS','FAIL') FROM m WHERE metric='evidence_coverage_pct')
  -- distractors largely excluded
  UNION ALL SELECT 'false_link_rate_within_bound', 'PASS',
    (SELECT IFF(value <= 5,'PASS','FAIL') FROM m WHERE metric='false_link_rate_pct')
  -- historical replay reproducibility
  UNION ALL SELECT 'historical_replay_accuracy', 'PASS',
    (SELECT IFF(value = 1,'PASS','FAIL') FROM m WHERE metric='historical_replay_accuracy')
  -- pipeline sanity: linker produced candidates, scorer retained a subset (not all, not none)
  UNION ALL SELECT 'candidates_generated', 'PASS',
    (SELECT IFF(value > 0,'PASS','FAIL') FROM m WHERE metric='candidate_edges')
  UNION ALL SELECT 'retained_strict_subset', 'PASS',
    (SELECT IFF((SELECT value FROM m WHERE metric='retained_edges')
              < (SELECT value FROM m WHERE metric='candidate_edges'),'PASS','FAIL'))
  UNION ALL SELECT 'retained_nonzero', 'PASS',
    (SELECT IFF(value > 0,'PASS','FAIL') FROM m WHERE metric='retained_edges')
)
SELECT c AS check_name, expected, actual, IFF(expected = actual,'PASS','FAIL') AS status
FROM checks ORDER BY status DESC, check_name;
