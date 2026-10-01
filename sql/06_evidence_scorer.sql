-- PROPAGATE :: Phase 4 :: 06_evidence_scorer.sql
-- Attaches 5 decomposable evidence components to every candidate edge, a composite score,
-- and an EVIDENCE CLASS badge that encodes how much we can claim (correlation vs causation).
-- Weights are explicit and tunable: textual + historical weighted highest (real evidence),
-- temporal + structural lowest (coincidence-prone). Retention threshold = 0.40.
--
-- Components (each in [0,1]):
--   temporal   = how tight the lag is within the allowed window
--   structural = strength of the shared-entity key path (order > supplier > warehouse > region)
--   magnitude  = how abnormal both endpoints are (z-score, or sentiment/assertion for docs)
--   textual    = document evidence (Cortex AI_CLASSIFY of comms/tickets); 0 where no doc exists
--   historical = recurrence of this relation on this entity in OTHER months
--
-- Causality: ONLY an explicit supplier statement earns CAUSAL_STATED. Everything else is
-- labelled by the strongest evidence present; pure temporal+structural overlap => TEMPORAL_STRUCTURAL,
-- never "causal".

CREATE OR REPLACE TABLE PROPAGATE.ANALYTICS.SCORED_EDGES AS
WITH comp AS (
  SELECT
    ce.edge_id, ce.from_event, ce.to_event, ce.from_type, ce.to_type,
    ce.from_function, ce.to_function, ce.relation, ce.lag_days, ce.lag_hours,
    ce.shared_entity_type, ce.shared_entity_id,
    af.event_time AS from_time, at.event_time AS to_time,
    GREATEST(0, 1 - ce.lag_days / l.max_lag_days) AS comp_temporal,
    CASE ce.shared_entity_type
      WHEN 'ORDER' THEN 1.0 WHEN 'SUPPLIER' THEN 0.8 WHEN 'WAREHOUSE' THEN 0.7
      WHEN 'REGION' THEN 0.5 ELSE 0.4 END AS comp_structural,
    ( IFF(af.deviation_score IS NOT NULL, LEAST(1, ABS(af.deviation_score)/3.0),
        IFF(af.event_type='SUPPORT_TICKET', GREATEST(0, -COALESCE(dsf.sentiment,0)),
        IFF(af.event_type='SCHEDULE_CHANGE', IFF(COALESCE(dsf.asserts_cause,FALSE),1.0,0.3), 0)))
    + IFF(at.deviation_score IS NOT NULL, LEAST(1, ABS(at.deviation_score)/3.0),
        IFF(at.event_type='SUPPORT_TICKET', GREATEST(0, -COALESCE(dst.sentiment,0)),
        IFF(at.event_type='SCHEDULE_CHANGE', IFF(COALESCE(dst.asserts_cause,FALSE),1.0,0.3), 0)))
    ) / 2.0 AS comp_magnitude,
    CASE ce.relation
      WHEN 'SCHEDULE_CHANGE_PRECEDES_DELAY' THEN IFF(COALESCE(dsf.asserts_cause,FALSE),1.0,0.2)
      WHEN 'LATE_DELIVERY_PRECEDES_COMPLAINT' THEN
        CASE COALESCE(dst.label,'OTHER') WHEN 'LATE_DELIVERY_COMPLAINT' THEN 1.0
             WHEN 'PRAISE' THEN 0.0 WHEN 'DAMAGE_COMPLAINT' THEN 0.4 ELSE 0.3 END
      WHEN 'COMPLAINT_ASSOCIATED_WITH_REFUND' THEN IFF(COALESCE(dsf.label,'')='LATE_DELIVERY_COMPLAINT',0.8,0.3)
      ELSE 0 END AS comp_textual,
    ( SELECT COUNT(DISTINCT TO_CHAR(e2.event_time,'YYYY-MM'))
        FROM PROPAGATE.ANALYTICS.CANDIDATE_EDGES c2
        JOIN PROPAGATE.ANALYTICS.EVENT_LOG e2 ON e2.event_id = c2.from_event
       WHERE c2.relation = ce.relation AND c2.shared_entity_id = ce.shared_entity_id
         AND TO_CHAR(e2.event_time,'YYYY-MM') <> TO_CHAR(af.event_time,'YYYY-MM') ) AS historical_count,
    COALESCE(dsf.asserts_cause,FALSE) AS from_asserts_cause
  FROM PROPAGATE.ANALYTICS.CANDIDATE_EDGES ce
  JOIN PROPAGATE.ANALYTICS.EVENT_LOG af ON af.event_id = ce.from_event
  JOIN PROPAGATE.ANALYTICS.EVENT_LOG at ON at.event_id = ce.to_event
  JOIN PROPAGATE.ANALYTICS.LAG_WINDOWS l ON l.relation = ce.relation
  LEFT JOIN PROPAGATE.ANALYTICS.DOC_SIGNALS dsf ON dsf.doc_id = af.text_ref
  LEFT JOIN PROPAGATE.ANALYTICS.DOC_SIGNALS dst ON dst.doc_id = at.text_ref
)
SELECT
  comp.* EXCLUDE (historical_count, from_asserts_cause),
  LEAST(1, historical_count/2.0) AS comp_historical,
  ROUND(0.15*comp_temporal + 0.15*comp_structural + 0.20*comp_magnitude
      + 0.25*comp_textual + 0.25*LEAST(1, historical_count/2.0), 4) AS evidence_score,
  CASE
    WHEN relation='SCHEDULE_CHANGE_PRECEDES_DELAY' AND from_asserts_cause THEN 'CAUSAL_STATED'
    WHEN comp_textual >= 0.5 THEN 'TEXT_SUPPORTED'
    WHEN LEAST(1, historical_count/2.0) >= 0.5 THEN 'HISTORICAL_SUPPORTED'
    WHEN comp_temporal > 0 AND comp_structural > 0 THEN 'TEMPORAL_STRUCTURAL'
    ELSE 'CORRELATION_ONLY' END AS evidence_class,
  (0.15*comp_temporal + 0.15*comp_structural + 0.20*comp_magnitude
      + 0.25*comp_textual + 0.25*LEAST(1, historical_count/2.0)) >= 0.40 AS retained
FROM comp;
