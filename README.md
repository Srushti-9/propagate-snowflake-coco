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
sql/        DDL, seed, engine SQL (phased)
python/     Snowpark data generator + helpers
streamlit/  Streamlit-in-Snowflake app
docs/       phase notes, Phase 0 capability matrix, validation results
```

## Status
Phase 0 (capability spike) pending.
