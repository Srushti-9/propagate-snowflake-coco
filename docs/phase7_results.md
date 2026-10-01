# Phase 7 — Streamlit-in-Snowflake App: Results

**Status: DEPLOYED + runtime-verified.** `STREAMLIT PROPAGATE.ANALYTICS.PROPAGATE_APP` (warehouse `COMPUTE_WH`).

## Deployment path (no local tooling)
No `snow`/`uv`/connector locally, so deployed by pure SQL: `CREATE STAGE` → `PUT` the app file → `CREATE STREAMLIT ... ROOT_LOCATION=@APP_STAGE`. Reproducible via `sql/08_streamlit_deploy.sql`; `streamlit/snowflake.yml` is included for teams that do have the `snow` CLI.

## App — 5 screens (`streamlit/streamlit_app.py`, SiS `get_active_session`)
1. **Propagation Overview** — all chains with headline KPIs (chain count, max intervention lead, affected entities, avg evidence); per-chain cards (signal → impact, lead time, intervention owner).
2. **Chain Investigation** — select a chain; ordered steps with **evidence-class badges**, lags, scores; earliest signal + intervention lead; timeline chart; dynamic **causality note**.
3. **Evidence Inspection** — per-edge breakdown of the 5 components (bar chart) + the actual source document text + plain-language causality caveat.
4. **Historical Comparison** — the 3 chains side by side + west-region revenue line showing baseline vs the recurring dips.
5. **Natural-Language Investigation** — Cortex **Search** over docs (`SEARCH_PREVIEW`) + a grounded **Cortex COMPLETE** summary with the causality guardrail baked into the prompt; notes the full `PROPAGATE_AGENT` is available in Snowflake Intelligence.

## Causality discipline in the UI
Evidence-class badges everywhere; screens 2/3 render an explicit note that temporal/structural-only links do **not** establish causation; the NL summary prompt forbids causal claims absent an explicit document statement.

## Runtime smoke tests (all green)
`V_CHAIN_SUMMARY`=3 · golden steps=6 · evidence join=6 · docs=12 · `SEARCH_PREVIEW`=4 hits · `COMPLETE` returns text · edge→doc lookup resolves. Object confirmed via `SHOW STREAMLITS` (url_id present).

## Open the app
Snowsight → **Projects → Streamlit → PROPAGATE** (database `PROPAGATE`, schema `ANALYTICS`).

## Next: Phase 8 — consolidated validation harness + historical replay (all metrics from section I).
