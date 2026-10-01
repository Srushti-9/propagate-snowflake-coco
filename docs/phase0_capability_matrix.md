# Phase 0 — Capability Spike Results

**Account:** `RN19749` · **Region:** GCP `me-central2` · **Role:** `ACCOUNTADMIN` · **WH:** `COMPUTE_WH` · **Version:** `10.35.101`
**Method:** throwaway DB `PROPAGATE_SPIKE` created, probed, then `DROP`ped. No persistent objects remain.

## Capability matrix

| Capability | Status | Evidence / Notes | Decision |
|---|---|---|---|
| `CORTEX.COMPLETE` (llama3.1-8b) | ✅ works | returned text | Use for text→event extraction |
| LLM structured extraction (JSON) | ✅ works | extracted `{cause:"port closure", delay_days:10}` from supplier comm | Primary extractor for `SUPPLIER_COMM` |
| `AI_CLASSIFY` | ✅ works | classified ticket → `complaint` | Ticket typing + edge-text relation class |
| `CORTEX.SENTIMENT` | ✅ works | −0.70 on angry ticket | Support magnitude signal |
| **Cortex Search Service** | ✅ **works** | `CREATE CORTEX SEARCH SERVICE` ok; `SEARCH_PREVIEW` returned relevant tickets with cosine + reranker scores | **PRIMARY** textual-evidence path |
| Raw embeddings `EMBED_TEXT_768` | ❌ returns NULL | tried `e5-base-v2`, `snowflake-arctic-embed-m*` → NULL/dim-mismatch | **Do NOT** hand-roll vector columns; rely on Search (embeds internally) |
| **Cortex Agent** (`CREATE AGENT`) | ✅ works | `SHOW AGENTS` recognized; created `SPIKE_AGENT` via SQL spec | NL investigation surface creatable via SQL |

## Go / No-Go
**GO.** Both headline Snowflake-native features (Cortex Search + Cortex Agent) are creatable in this account/region, and all required AI functions work.

## Design confirmations
1. **Textual evidence = Cortex Search (primary).** Raw embeddings are unavailable here, but Search embeds internally and works — this validates the earlier decision to avoid manual vector columns. AI-function fallback (`AI_CLASSIFY`/`COMPLETE` over raw doc tables) remains as backup but is **not needed**.
2. **Agent via SQL spec** (`CREATE AGENT ... FROM SPECIFICATION`) is viable; wire it to the Search service + semantic view + a chain-lookup proc in Phase 6.
3. **Extraction** of events from `SUPPLIER_COMM` will use `CORTEX.COMPLETE` with a strict-JSON prompt.

## MVP scope locked (per review)
- Unstructured sources in MVP: **SUPPLIER_COMMS + SUPPORT_TICKETS** only; model designed so `INCIDENT_REPORTS` + `WAREHOUSE_REPORTS` can be added later without restructuring.
- Data: **deterministic synthetic generator (fixed seed)** with injected true chains + distractor events + historical cases.
