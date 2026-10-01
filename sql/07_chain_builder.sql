-- PROPAGATE :: Phase 5 :: 07_chain_builder.sql
-- Reconstructs propagation CHAINS from retained SCORED_EDGES.
-- Method:
--   1. best_parent: for each event keep its single highest-evidence retained incoming edge (forest).
--   2. walk: recursively trace backward from every revenue-impact node to its root.
--   3. chosen: one chain per root = the anchor path with the highest total evidence.
--   4. CHAINS: summary + earliest signal + earliest intervention candidate.
-- Earliest intervention = the earliest node that is observable AND has a decision owner (business_function).
--   Presented as "earliest observable + actionable point", NOT a counterfactual causal guarantee.

CREATE OR REPLACE TABLE PROPAGATE.ANALYTICS.CHAIN_EDGES AS
WITH best_parent AS (
  SELECT edge_id, from_event, to_event, relation, evidence_score, evidence_class, lag_days
  FROM PROPAGATE.ANALYTICS.SCORED_EDGES
  WHERE retained
  QUALIFY ROW_NUMBER() OVER (PARTITION BY to_event ORDER BY evidence_score DESC, lag_days ASC) = 1
),
walk AS (
  SELECT bp.to_event AS anchor, 1 AS depth, bp.edge_id, bp.from_event, bp.to_event,
         bp.relation, bp.evidence_score, bp.evidence_class
  FROM best_parent bp
  WHERE bp.to_event LIKE 'EVT_BM_%'
  UNION ALL
  SELECT w.anchor, w.depth+1, bp.edge_id, bp.from_event, bp.to_event,
         bp.relation, bp.evidence_score, bp.evidence_class
  FROM walk w JOIN best_parent bp ON bp.to_event = w.from_event
),
anchor_summary AS (
  SELECT anchor, COUNT(*) nedges, SUM(evidence_score) total_score, MAX(depth) maxdepth
  FROM walk GROUP BY anchor
),
anchor_root AS (
  SELECT w.anchor, w.from_event AS root_event
  FROM walk w JOIN anchor_summary s ON s.anchor=w.anchor AND w.depth=s.maxdepth
),
chosen AS (
  SELECT a.anchor, ar.root_event, a.total_score, a.nedges, a.maxdepth
  FROM anchor_summary a JOIN anchor_root ar ON ar.anchor=a.anchor
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ar.root_event ORDER BY a.total_score DESC, a.nedges DESC) = 1
)
SELECT 'CHAIN_'||REPLACE(c.root_event,'EVT_SC_','') AS chain_id,
       (c.maxdepth - w.depth + 1) AS step_no,
       w.edge_id, w.from_event, w.to_event, w.relation, w.evidence_score, w.evidence_class
FROM chosen c JOIN walk w ON w.anchor = c.anchor;

CREATE OR REPLACE TABLE PROPAGATE.ANALYTICS.CHAINS AS
WITH ce AS (
  SELECT *, MIN(step_no) OVER (PARTITION BY chain_id) mins, MAX(step_no) OVER (PARTITION BY chain_id) maxs
  FROM PROPAGATE.ANALYTICS.CHAIN_EDGES
),
agg AS (
  SELECT chain_id,
    MAX(IFF(step_no=mins, from_event, NULL)) AS root_event,
    MAX(IFF(step_no=maxs, to_event,  NULL)) AS impact_event,
    COUNT(*) AS edge_count, COUNT(*)+1 AS node_count,
    ROUND(SUM(evidence_score),4) AS total_score,
    ROUND(MIN(evidence_score),4) AS min_edge_score,
    ROUND(AVG(evidence_score),4) AS avg_edge_score,
    BOOLAND_AGG(evidence_class IN ('CAUSAL_STATED','TEXT_SUPPORTED','HISTORICAL_SUPPORTED')) AS all_edges_supported
  FROM ce GROUP BY chain_id
),
nodes AS (
  SELECT c.chain_id, COUNT(DISTINCT el.entity_id) AS affected_entity_count
  FROM PROPAGATE.ANALYTICS.CHAIN_EDGES c
  JOIN PROPAGATE.ANALYTICS.EVENT_LOG el ON el.event_id IN (c.from_event, c.to_event)
  GROUP BY c.chain_id
)
SELECT a.chain_id, a.root_event, re.event_type AS root_type, re.event_time AS root_time,
       re.business_function AS earliest_signal_function,
       a.impact_event, ie.event_type AS impact_type, ie.event_time AS impact_time, ie.link_region AS impact_region,
       a.edge_count, a.node_count, n.affected_entity_count,
       a.total_score, a.min_edge_score, a.avg_edge_score, a.all_edges_supported,
       a.root_event AS earliest_intervention_event,
       re.business_function AS intervention_function,
       DATEDIFF('day', re.event_time, ie.event_time) AS intervention_lead_days,
       CURRENT_TIMESTAMP() AS created_at
FROM agg a
JOIN PROPAGATE.ANALYTICS.EVENT_LOG re ON re.event_id = a.root_event
JOIN PROPAGATE.ANALYTICS.EVENT_LOG ie ON ie.event_id = a.impact_event
JOIN nodes n ON n.chain_id = a.chain_id;
