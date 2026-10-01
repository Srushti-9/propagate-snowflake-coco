# PROPAGATE — Demo Script (golden path)

~5-minute walkthrough. Everything below is live in Snowflake account `RN19749`, database `PROPAGATE`.

## 0. One-line pitch
> PROPAGATE reconstructs **evidence-backed propagation chains** — from an earliest business
> signal to downstream revenue impact — and tells you *where you could have intervened earlier*,
> without ever mistaking correlation for causation.

## 1. The problem (30s)
A supplier quietly changed a delivery schedule on **Sept 1**. Eighteen days later the **west-region
revenue** dipped. In between: a late shipment, a warehouse backlog, a late delivery, a customer
complaint, and a refund — each owned by a different team, none of whom saw the whole picture.

## 2. Open the app (30s)
Snowsight → **Projects → Streamlit → PROPAGATE** (`ANALYTICS.PROPAGATE_APP`).
**Screen 1 — Overview:** 3 chains detected; headline KPI **max intervention lead = 18 days**.

## 3. Golden chain investigation (90s)
**Screen 2 — Chain Investigation → `CHAIN_SC-G1`.** Walk the 7-node chain:

```
Supplier schedule change (Sep 1)  →  Shipment delay  →  Warehouse backlog
  →  Late delivery  →  Support complaint  →  Refund  →  West revenue impact (Sep 19)
```

Point out, per edge:
- **evidence-class badge** (step 1 = `CAUSAL_STATED`, score 0.87 — the comm text states the cause),
- the **lag** and **5-component score**,
- **earliest signal = supplier comm**, **intervention lead = 18 days**, owner = **SUPPLIER**.

Read the **causality note**: temporal/structural links are flagged as *not causation* unless text/history backs them.

## 4. Evidence inspection (60s)
**Screen 3 — Evidence Inspection** on the step-1 edge: the 5-component bar (temporal / structural /
magnitude / textual / historical) plus the **actual supplier-comm text** that grounds the textual
score. Contrast with a dropped distractor: the on-schedule comm **SC-D1** scored **0.38** and never
entered a chain.

## 5. It's not a one-off (45s)
**Screen 4 — Historical Comparison:** the same engine reconstructs **June (13-day lead)** and
**July (14-day lead)** incidents from the same supplier→west-revenue pattern. The west-revenue line
shows baseline vs the three recurring dips. → This is a *recurring* failure mode, now detectable early.

## 6. Ask in natural language (45s)
**Screen 5 — NL Investigation:** type *"What started the west-region revenue drop and where could we
have intervened?"* → Cortex **Search** over supplier comms + support tickets returns grounded snippets;
**Cortex COMPLETE** summarizes with the causality guardrail baked in (no causal claim without an
explicit document statement). Full `PROPAGATE_AGENT` is also available in Snowflake Intelligence.

## 7. Prove it (45s) — CoCo CLI
```sql
-- the scorecard
SELECT * FROM PROPAGATE.ANALYTICS.VALIDATION_METRICS ORDER BY metric;
-- the assertions (12/12 PASS)
-- (run sql/phase8_tests.sql)
```
Headline: **F1 = 1.0 · precision = recall = 1.0 · earliest-signal 3/3 · evidence coverage 100% ·
historical replay 2/2 · false-link rate 0.7%** — all measured against injected ground truth.

## 8. Close (15s)
> Structured + unstructured data, Cortex AI, Cortex Search, a Cortex Agent, a semantic view, and a
> Streamlit app — built and validated with the Snowflake CoCo CLI in the loop. The product isn't a
> dashboard; it's the **chain** — and the earlier intervention it surfaces.

---
### Fallback (no Snowsight): pure SQL
```sql
SELECT * FROM PROPAGATE.ANALYTICS.V_CHAIN_SUMMARY ORDER BY chain_id;
SELECT step_no, relation, evidence_class, lag_days, evidence_score
FROM PROPAGATE.ANALYTICS.V_CHAIN_DETAIL WHERE chain_id='CHAIN_SC-G1' ORDER BY step_no;
```
