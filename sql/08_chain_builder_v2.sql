-- PROPAGATE :: Phase 2.2 :: 08_chain_builder_v2.sql
-- Graph-based forward-walk chain reconstruction.
-- Replaces the backward-walk approach in 07_chain_builder.sql.
--
-- Algorithm:
--   1. ROOT_CANDIDATES: score all in-degree=0 nodes in the retained graph
--   2. FORWARD WALK: from each root, traverse downstream via best outgoing edge
--   3. PATH COHERENCE: score each discovered path on evidence, progression, length
--   4. CHAIN SELECTION: keep highest-coherence path per root, discard weak paths
--   5. OUTPUT: CHAIN_EDGES + CHAINS (same contract as v1 + chain_status, coherence_score)
--
-- HARD CONSTRAINTS:
--   * Does NOT read GROUND_TRUTH_EDGES or CHALLENGE_GROUND_TRUTH_EDGES
--   * Does NOT modify candidate generation or evidence scoring
--   * Does NOT hard-code any specific chain or entity
--   * Does NOT use LLM calls
--   * Operates entirely on SCORED_EDGES (retained edges)

-- ===================================================================
-- STEP 1: ROOT CANDIDATES
-- Nodes with in-degree=0 in the retained-edge graph, scored by
-- event semantics + best outgoing edge quality.
-- ===================================================================
CREATE OR REPLACE TABLE PROPAGATE.ANALYTICS.ROOT_CANDIDATES AS
WITH retained_targets AS (
  SELECT DISTINCT to_event FROM PROPAGATE.ANALYTICS.SCORED_EDGES WHERE retained
),
retained_sources AS (
  SELECT DISTINCT from_event FROM PROPAGATE.ANALYTICS.SCORED_EDGES WHERE retained
),
roots AS (
  SELECT s.from_event AS event_id
  FROM retained_sources s
  LEFT JOIN retained_targets t ON t.to_event = s.from_event
  WHERE t.to_event IS NULL
),
root_info AS (
  SELECT r.event_id, el.event_type, el.business_function, el.event_time, el.deviation_score,
    -- Event-type signal: SCHEDULE_CHANGE is the strongest root indicator
    CASE el.event_type
      WHEN 'SCHEDULE_CHANGE' THEN 1.0
      WHEN 'SHIPMENT_DELAY' THEN 0.6
      WHEN 'ORDER_DELIVERY' THEN 0.3
      WHEN 'SUPPORT_TICKET' THEN 0.2
      WHEN 'REFUND' THEN 0.1
      ELSE 0.1
    END AS type_score,
    -- Best outgoing edge quality
    (SELECT MAX(se.evidence_score) FROM PROPAGATE.ANALYTICS.SCORED_EDGES se
     WHERE se.retained AND se.from_event = r.event_id) AS best_out_score,
    -- Evidence class of best outgoing edge
    (SELECT se.evidence_class FROM PROPAGATE.ANALYTICS.SCORED_EDGES se
     WHERE se.retained AND se.from_event = r.event_id
     ORDER BY se.evidence_score DESC LIMIT 1) AS best_out_class,
    -- Out-degree
    (SELECT COUNT(*) FROM PROPAGATE.ANALYTICS.SCORED_EDGES se
     WHERE se.retained AND se.from_event = r.event_id) AS out_degree
  FROM roots r
  JOIN PROPAGATE.ANALYTICS.EVENT_LOG el ON el.event_id = r.event_id
)
SELECT event_id, event_type, business_function, event_time, deviation_score,
  type_score, best_out_score, best_out_class, out_degree,
  ROUND(0.40 * type_score
      + 0.35 * COALESCE(best_out_score, 0)
      + 0.25 * CASE best_out_class
                 WHEN 'CAUSAL_STATED' THEN 1.0
                 WHEN 'TEXT_SUPPORTED' THEN 0.7
                 WHEN 'HISTORICAL_SUPPORTED' THEN 0.5
                 WHEN 'TEMPORAL_STRUCTURAL' THEN 0.2
                 ELSE 0.1 END, 4) AS root_score
FROM root_info;

-- ===================================================================
-- STEP 2: FORWARD WALK
-- From each qualifying root (root_score >= 0.30), traverse forward
-- through retained edges. At each node, take the single best outgoing
-- edge (highest evidence_score, tie-break: shortest lag).
-- Max depth = 10 to prevent runaway recursion.
-- ===================================================================
CREATE OR REPLACE TABLE PROPAGATE.ANALYTICS.CHAIN_EDGES AS
WITH best_child AS (
  SELECT from_event, to_event, edge_id, relation, evidence_score, evidence_class, lag_days
  FROM PROPAGATE.ANALYTICS.SCORED_EDGES
  WHERE retained
  QUALIFY ROW_NUMBER() OVER (PARTITION BY from_event ORDER BY evidence_score DESC, lag_days ASC) = 1
),
walk AS (
  -- Seed: each qualifying root's best outgoing edge
  SELECT
    rc.event_id AS root_event,
    rc.root_score,
    1 AS depth,
    bc.edge_id, bc.from_event, bc.to_event,
    bc.relation, bc.evidence_score, bc.evidence_class
  FROM PROPAGATE.ANALYTICS.ROOT_CANDIDATES rc
  JOIN best_child bc ON bc.from_event = rc.event_id
  WHERE rc.root_score >= 0.30
  UNION ALL
  -- Recurse: follow the best child of the current to_event
  SELECT
    w.root_event, w.root_score, w.depth + 1,
    bc.edge_id, bc.from_event, bc.to_event,
    bc.relation, bc.evidence_score, bc.evidence_class
  FROM walk w
  JOIN best_child bc ON bc.from_event = w.to_event
  WHERE w.depth < 10
)
SELECT
  root_event AS chain_id_raw,
  depth AS step_no,
  edge_id, from_event, to_event,
  relation, evidence_score, evidence_class
FROM walk;

-- ===================================================================
-- STEP 3: PATH COHERENCE SCORING + CHAIN ASSEMBLY
-- Score each path and produce the CHAINS summary table.
-- ===================================================================
CREATE OR REPLACE TABLE PROPAGATE.ANALYTICS.CHAINS AS
WITH path_edges AS (
  SELECT *, MIN(step_no) OVER (PARTITION BY chain_id_raw) AS min_step,
            MAX(step_no) OVER (PARTITION BY chain_id_raw) AS max_step
  FROM PROPAGATE.ANALYTICS.CHAIN_EDGES
),
path_agg AS (
  SELECT chain_id_raw,
    MAX(IFF(step_no = min_step, from_event, NULL)) AS root_event,
    MAX(IFF(step_no = max_step, to_event, NULL)) AS impact_event,
    COUNT(*) AS edge_count,
    COUNT(*) + 1 AS node_count,
    ROUND(AVG(evidence_score), 4) AS avg_edge_score,
    ROUND(MIN(evidence_score), 4) AS min_edge_score,
    ROUND(SUM(evidence_score), 4) AS total_score,
    COUNT(DISTINCT relation) AS distinct_transitions,
    BOOLAND_AGG(evidence_class IN ('CAUSAL_STATED','TEXT_SUPPORTED','HISTORICAL_SUPPORTED')) AS all_edges_supported
  FROM path_edges
  GROUP BY chain_id_raw
),
path_detail AS (
  SELECT pa.*,
    re.event_type AS root_type, re.event_time AS root_time,
    re.business_function AS earliest_signal_function,
    ie.event_type AS impact_type, ie.event_time AS impact_time,
    ie.link_region AS impact_region,
    -- Business-function progression: how many distinct functions does the path cross?
    (SELECT COUNT(DISTINCT el2.business_function)
     FROM PROPAGATE.ANALYTICS.CHAIN_EDGES ce
     JOIN PROPAGATE.ANALYTICS.EVENT_LOG el2 ON el2.event_id IN (ce.from_event, ce.to_event)
     WHERE ce.chain_id_raw = pa.chain_id_raw) AS func_count,
    -- Root score (from ROOT_CANDIDATES)
    COALESCE((SELECT root_score FROM PROPAGATE.ANALYTICS.ROOT_CANDIDATES rc
              WHERE rc.event_id = pa.root_event), 0.3) AS root_score,
    -- Is the impact a revenue/financial event?
    CASE ie.event_type
      WHEN 'REVENUE' THEN 'complete'
      WHEN 'REFUND' THEN 'partial_financial'
      ELSE 'partial'
    END AS chain_status
  FROM path_agg pa
  JOIN PROPAGATE.ANALYTICS.EVENT_LOG re ON re.event_id = pa.root_event
  JOIN PROPAGATE.ANALYTICS.EVENT_LOG ie ON ie.event_id = pa.impact_event
),
coherence AS (
  SELECT pd.*,
    -- Coherence score formula (transparent, documented):
    --   0.30 * avg_evidence      (path quality)
    --   0.20 * min_evidence      (weakest-link strength)
    --   0.20 * function_prog     (business-function diversity)
    --   0.15 * path_length_bonus (longer coherent paths preferred)
    --   0.15 * root_quality      (root signal strength)
    ROUND(
      0.30 * avg_edge_score
    + 0.20 * min_edge_score
    + 0.20 * LEAST(1.0, func_count / 4.0)
    + 0.15 * LEAST(1.0, edge_count / 4.0)
    + 0.15 * root_score
    , 4) AS coherence_score
  FROM path_detail pd
),
-- Affected entity count
nodes AS (
  SELECT ce.chain_id_raw, COUNT(DISTINCT el.entity_id) AS affected_entity_count
  FROM PROPAGATE.ANALYTICS.CHAIN_EDGES ce
  JOIN PROPAGATE.ANALYTICS.EVENT_LOG el ON el.event_id IN (ce.from_event, ce.to_event)
  GROUP BY ce.chain_id_raw
),
-- Generate chain IDs: prefer 'CHAIN_' + root ID suffix
final AS (
  SELECT
    'CHAIN_' || REPLACE(REPLACE(c.root_event, 'EVT_SC_', ''), 'EVT_', '') AS chain_id,
    c.root_event, c.root_type, c.root_time, c.earliest_signal_function,
    c.impact_event, c.impact_type, c.impact_time, c.impact_region,
    c.edge_count, c.node_count, n.affected_entity_count,
    c.total_score, c.min_edge_score, c.avg_edge_score, c.all_edges_supported,
    c.root_event AS earliest_intervention_event,
    c.earliest_signal_function AS intervention_function,
    DATEDIFF('day', c.root_time, c.impact_time) AS intervention_lead_days,
    c.chain_status,
    c.coherence_score,
    c.root_score,
    c.distinct_transitions,
    CURRENT_TIMESTAMP() AS created_at
  FROM coherence c
  JOIN nodes n ON n.chain_id_raw = c.chain_id_raw
  WHERE c.coherence_score >= 0.30
)
SELECT * FROM final;

-- Backfill chain_id into CHAIN_EDGES for join compatibility
-- (chain_id_raw = root_event, need to map to chain_id)
CREATE OR REPLACE TABLE PROPAGATE.ANALYTICS.CHAIN_EDGES AS
SELECT
  ch.chain_id,
  ce.step_no, ce.edge_id, ce.from_event, ce.to_event,
  ce.relation, ce.evidence_score, ce.evidence_class
FROM PROPAGATE.ANALYTICS.CHAIN_EDGES ce
JOIN PROPAGATE.ANALYTICS.CHAINS ch ON ch.root_event = ce.chain_id_raw;

-- ===================================================================
-- STEP 4: RECREATE VIEWS (same contract for Streamlit compatibility)
-- ===================================================================
CREATE OR REPLACE VIEW PROPAGATE.ANALYTICS.V_CHAIN_SUMMARY AS
SELECT
  chain_id, root_event, root_type, root_time, earliest_signal_function,
  impact_event, impact_type, impact_time, impact_region,
  edge_count, node_count, affected_entity_count,
  total_score, min_edge_score, avg_edge_score, all_edges_supported,
  earliest_intervention_event, intervention_function, intervention_lead_days,
  chain_status, coherence_score,
  created_at
FROM PROPAGATE.ANALYTICS.CHAINS;

CREATE OR REPLACE VIEW PROPAGATE.ANALYTICS.V_CHAIN_DETAIL AS
SELECT
  ce.chain_id, ce.step_no, ce.edge_id,
  ce.from_event, ce.to_event, ce.relation,
  ce.evidence_score, ce.evidence_class,
  fe.event_type AS from_type, fe.business_function AS from_function,
  fe.entity_id AS from_entity, fe.event_time AS from_time,
  te.event_type AS to_type, te.business_function AS to_function,
  te.entity_id AS to_entity, te.event_time AS to_time,
  se.lag_days,
  se.comp_temporal, se.comp_structural, se.comp_magnitude, se.comp_textual, se.comp_historical
FROM PROPAGATE.ANALYTICS.CHAIN_EDGES ce
JOIN PROPAGATE.ANALYTICS.EVENT_LOG fe ON fe.event_id = ce.from_event
JOIN PROPAGATE.ANALYTICS.EVENT_LOG te ON te.event_id = ce.to_event
LEFT JOIN PROPAGATE.ANALYTICS.SCORED_EDGES se ON se.edge_id = ce.edge_id;
