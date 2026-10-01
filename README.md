# PROPAGATE

AI-native enterprise intelligence that reconstructs **evidence-backed propagation chains** —
from an earliest business signal to downstream impact — across business functions.

> Core question: *"What started this, how did it spread, what evidence connects the
> events, and where could we potentially have intervened earlier?"*

Prototype domain (supply chain):

```
Supplier comms → Shipment → Warehouse/Delivery → Customer support → Refund → Revenue impact
```

## Causality principle
Correlation is **not** treated as causation. Every chain edge carries an explicit
evidence class: `CORRELATION_ONLY`, `TEMPORAL_STRUCTURAL`, `HISTORICAL_SUPPORTED`,
`TEXT_SUPPORTED`, or `CAUSAL_STATED`. Where causal evidence is insufficient, the system
says so.

## Stack
- Snowflake (DB `PROPAGATE`: schemas `CORE`, `DOCS`, `ANALYTICS`; `COMPUTE_WH`)
- Cortex: Search (preferred) with AI-function fallback, `AI_CLASSIFY`, `SENTIMENT`, `COMPLETE`
- Streamlit-in-Snowflake UI
- Snowflake CoCo CLI as part of the dev workflow

## Layout
```
sql/            DDL, seed, engine SQL + per-phase test suites (01..09, phaseN_tests)
cortex_project/ agent-studio specs (semantic view + Cortex Agent)
streamlit/      Streamlit-in-Snowflake app + manifest
docs/           per-phase results, Phase 0 capability matrix, demo script
```

## Pipeline (SQL, phased + idempotent)
```
01 setup → 02 tables → 03 seed (deterministic ground truth) → 04 event spine
→ 05 candidate linker → 06 evidence scorer → 07 chain builder
→ 08 streamlit deploy → 09 validation scorecard
```

## Status — COMPLETE (Phases 0–8)
Validated against injected ground truth (`sql/phase8_tests.sql`, 12/12 PASS):

| metric | result |
|---|---|
| chain reconstruction F1 / precision / recall | **1.0 / 1.0 / 1.0** |
| chains reconstructed | **3** (golden + 2 historical) |
| earliest-signal detection | **3/3** chains rooted at true early signal |
| evidence coverage | **100%** (≥2 components per chain edge) |
| historical replay | **2/2** |
| false-link rate | **0.7%** |

Golden chain: supplier schedule change → … → west revenue impact, **18-day intervention lead**.
See `docs/demo_script.md` for the walkthrough and `docs/phase8_results.md` for the full scorecard.

## Reproduce
Run `sql/01_setup.sql` … `sql/09_validation.sql` in order (CoCo CLI / Snowsight), then
`sql/phaseN_tests.sql` to re-verify. Streamlit: `sql/08_streamlit_deploy.sql`.
