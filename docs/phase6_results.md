# Phase 6 — Semantic View + Cortex Agent: Results

**Status: PASS. NL investigation works end-to-end with causality discipline.**

## Objects created
- `ANALYTICS.V_CHAIN_DETAIL`, `ANALYTICS.V_CHAIN_SUMMARY` — denormalized chain views (UI + grounding).
- `ANALYTICS.PROPAGATE_ANALYTICS` — **semantic view** (Cortex Analyst) over `CHAINS` + `CORE.BUSINESS_METRICS` + `EVENT_LOG`, with 3 verified queries. Built via `cortex agent-studio sv-generate` → `sv-write` → `sv-deploy`. Spec tracked at `cortex_project/PROPAGATE_ANALYTICS.sv.yaml`.
- `ANALYTICS.PROPAGATE_AGENT` — **Cortex Agent** wired to two tools:
  - `propagation_metrics` → `cortex_analyst_text_to_sql` on the semantic view
  - `doc_evidence` → `cortex_search` on `DOCS.DOC_SEARCH`
  Instructions enforce the causality discipline (evidence_class labels; never claim causation from correlation). Spec at `cortex_project/PROPAGATE_AGENT.agent.yaml`.

## CoCo CLI role
Entire AI layer built through the `cortex agent-studio` CLI subcommands (sv-generate/write/deploy, agent-write/deploy) — specs are versioned in `cortex_project/`.

## End-to-end validation (`cortex agents run`)
Question: *"Which propagation chain had the longest intervention lead time, and what was the earliest signal?"*
Agent answer (abridged):
> Longest lead time: **CHAIN_SC-G1 at 18 days**. Earliest signal: `EVT_SC_SC-G1` — a SUPPLIER schedule-change from SUP-ACME on 2026-09-01, evidence_class **CAUSAL_STATED** (document explicitly names a port closure). Impact: west revenue deviation on 2026-09-19. 7 nodes, avg edge score 0.64.
> **Causality note:** only the first link is CAUSAL_STATED; the end-to-end revenue attribution is temporal-structural, *not* proven causation.

This demonstrates the agent combining **Analyst (metrics)** + **Search (document evidence)** and honoring the causality principle unprompted.

## Validation (`sql/phase6_tests.sql`)
views_present=2 · semantic_view_present=1 · search_service_present=1 · agent_present=1 · Analyst grounds on the semantic view (generates correct SQL). **All PASS.**
(Run SHOW+RESULT_SCAN checks one at a time — concurrent runs collide on LAST_QUERY_ID.)

## Cortex Agent note
Agent is creatable + runnable via SQL/CLI (confirmed Phase 0 + here). It can also be surfaced in Snowflake Intelligence (CoWork) if desired — not required for the prototype.

## Next: Phase 7 — Streamlit-in-Snowflake app (5 screens over these objects).
