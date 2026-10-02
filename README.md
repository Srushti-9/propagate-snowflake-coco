# PROPAGATE

### From the First Signal to the Business Impact

**Hackathon Challenge: Risk, Fraud & Regulatory Intelligence Copilot**

**PROPAGATE** is an evidence-backed risk propagation intelligence system built on Snowflake. It reconstructs how an early risk signal propagates across business functions and eventually becomes measurable business impact — connecting structured operational events with unstructured business documents to produce inspectable propagation chains.

The current prototype demonstrates the concept using **supply-chain operational risk**. The same underlying intelligence pattern is designed to generalize to fraud investigation and regulatory/compliance risk analysis.

PROPAGATE does not claim to prove causality. It identifies evidence-backed propagation relationships, surfaces both supporting and contradictory evidence, and reports where the available evidence is incomplete.

---

## The Risk Intelligence Problem

Enterprise risk signals are fragmented across operational systems, transactions, business metrics, support channels, communications, and documents. An early risk signal may appear in one system while its eventual business impact emerges much later in an entirely different part of the organization.

```
Early risk signal
       ↓  days or weeks
Operational effects
       ↓
Downstream disruption
       ↓
Customer/business impact
       ↓
Measurable financial loss
```

The challenge is not simply detecting an anomaly. The challenge is answering:

> *"What was the earliest meaningful risk signal, how did it propagate across business functions, what evidence connects each step, and where could we potentially have detected it earlier?"*

Conventional dashboards detect that something changed. They do not reconstruct how a risk signal propagated through multiple systems over time, or attach evidence to each step in the path.

---

## Why PROPAGATE Fits the Risk/Fraud/Regulatory Challenge

PROPAGATE treats a business risk as a **propagation problem**. An early signal moves through multiple entities, processes, and business functions before becoming measurable impact. The system reconstructs that path and attaches evidence to each relationship:

**Signal → Propagation → Evidence → Impact → Detection Opportunity**

This abstraction supports multiple risk domains:

| Risk domain | Signal | Propagation | Impact |
|------------|--------|-------------|--------|
| **Operational risk** (implemented) | Supplier disruption | Shipment → warehouse → delivery → support | Revenue decline |
| **Fraud investigation** (future) | Suspicious transaction | Account/network activity → exposure spread | Financial loss |
| **Regulatory risk** (future) | Regulatory change/signal | Affected process/product → compliance gap | Business/legal impact |

The current prototype implements **operational/supply-chain risk** as the demonstration domain. Fraud and regulatory applications are potential future extensions of the same propagation framework — they are not implemented in the current prototype.

---

## What PROPAGATE Does

### The Propagation Chain

A propagation chain connects an early risk signal to downstream business impact. Each relationship in the chain carries:

- **Temporal evidence** — event ordering and time gaps
- **Entity/structural evidence** — shared suppliers, warehouses, orders, customers
- **Document evidence** — supporting or contradicting text from business communications
- **Evidence classification** — SUPPORTS, CONTRADICTS, CONTEXT, or missing
- **Uncertainty** — evidence gaps and weak links are explicitly reported

PROPAGATE does not ask an LLM to generate a propagation story. Instead, it uses a layered approach:

1. **Event normalization** — structured and unstructured events are normalized into a single typed timeline with deviation scores
2. **Candidate relationships** — a domain transition graph identifies candidate propagation edges based on temporal precedence and shared entities
3. **Evidence-based scoring** — each candidate is scored across five transparent components (temporal, structural, magnitude, textual, historical)
4. **Graph-based chain reconstruction** — forward-walk discovery builds chains from scored root candidates through best-evidence paths
5. **AI evidence enrichment** — Cortex AI classifies whether business documents support, contradict, or are contextual for each relationship
6. **Investigation layer** — a Cortex Agent lets analysts explore the resulting intelligence using natural language

The LLM enriches relationships with document evidence and provides an investigation interface. It does not discover the chain structure.

---

## Demonstrated Risk Scenario

The working prototype demonstrates **supply-chain operational risk** — how a supplier disruption propagates into a revenue decline:

### West Region Revenue Decline — September 2026

```
Sep 01    Supplier schedule disruption (SUP-ACME)           SUPPLIER
              ↓  2 days
Sep 03    Shipment delay (SH-G1)                            SHIPPING
              ↓  2 days
Sep 05    Warehouse backlog (WH-WEST)                       WAREHOUSE
              ↓  11 days
Sep 16    Late delivery (OR-G4)                             FULFILLMENT
              ↓  same day
Sep 16    Customer complaint (ST-G4)                        SUPPORT
              ↓  3 days
Sep 19    Refund issued (RF-G4)                             FINANCE
              ↓  1 day
Sep 20    Revenue impact (west region)                      FINANCE
```

| Metric | Value |
|--------|-------|
| Earliest meaningful signal | Sep 01, 2026 — supplier schedule disruption |
| Observed business impact | Sep 20, 2026 — west-region revenue decline |
| Earliest detection opportunity | **19 days** before business impact |
| Propagation steps | 6 |
| Evidence coverage | 6/6 edges have document evidence |
| Business impact | West daily revenue fell from ~$125,600 to ~$86,200 |
| Historical recurrence | Same pattern observed in June (13-day lead) and July (14-day lead) |

The root relationship is classified `CAUSAL_STATED` — the supplier communication explicitly states: *"Due to a port closure we are moving your delivery window for WH-WEST back by approximately 10 days."*

---

## The Key Insight

> **PROPAGATE identifies the earliest meaningful risk signal and measures how long it took for the downstream business impact to become visible.**

For the demonstrated scenario, the supplier's port-closure notice was available **19 days** before the revenue impact appeared. The same pattern recurred in June 2026 (13-day lead) and July 2026 (14-day lead).

This creates a **potential detection/intervention opportunity** — a window where the risk signal was observable before the business impact materialized.

> This is an opportunity for earlier detection or intervention, not a guarantee that the downstream outcome would have been prevented. Identifying an earlier signal does not establish that acting on it would have changed the result.

---

## Evidence, Not Just a Story

Each propagation relationship carries attached evidence that users can inspect:

**Structural evidence** — temporal precedence, shared entities, historical recurrence, metric deviation, and a composite score from five decomposable components.

**Document evidence** — classified by Cortex AI:

| Classification | Meaning |
|---------------|---------|
| **SUPPORTS** | Document evidence is consistent with the proposed relationship |
| **CONTRADICTS** | Document evidence weakens or conflicts with the relationship |
| **CONTEXT** | Document is relevant but does not establish support or contradiction |
| **No document evidence** | No matching document found — the relationship relies on structured data only |

**Contradictions are deliberately surfaced.** When a supplier communication states *"your shipment is on schedule"* but structured data suggests a delay, the system records and displays the contradiction rather than hiding it.

> PROPAGATE makes the reasoning path inspectable rather than presenting an unexplained AI conclusion.

Across the prototype: 26 supporting document matches, 4 contradicting matches, and 10 contextual matches from 18 documents.

---

## Cortex Investigation Agent

The Cortex Agent is the **investigation interface** over the propagation intelligence. It does not independently discover or invent propagation chains.

**Example investigation questions:**

- *"Why did West-region revenue decline in September 2026?"*
- *"What started the problem?"*
- *"What evidence supports the shipment-delay to warehouse-backlog relationship?"*
- *"Was there contradictory evidence?"*
- *"Could we have detected this earlier?"*
- *"Have we seen a similar pattern before?"*
- *"Which link has the weakest evidence?"*
- *"What evidence is missing?"*

**Anti-hallucination.** When asked *"Why did East region revenue decline because of SUP-ACME?"*, the Agent responds that no evidence-backed propagation chain supports that relationship. It does not manufacture a connection.

> The Agent investigates computed propagation intelligence; it does not invent the propagation chain from scratch.

---

## Architecture

```mermaid
graph TB
    User([Analyst / Judge])

    subgraph "Investigation Layer"
        SUI[Streamlit UI<br/>Chain-first Investigation]
        AGT[Cortex Agent<br/>Natural-language Investigation]
    end

    subgraph "Risk Propagation Intelligence"
        CHN[Propagation Chains<br/>Graph-based Discovery]
        EVD[AI Evidence Layer<br/>Document Classification]
        HST[Historical Comparison]
    end

    subgraph "Cortex AI Services"
        CSS[Cortex Search<br/>Document Retrieval]
        CAI[Cortex AI Functions<br/>Evidence Classification]
        CAN[Cortex Analyst<br/>Semantic View Queries]
    end

    subgraph "Snowflake Data Layer"
        CORE[Structured Events<br/>Suppliers · Shipments · Orders<br/>Warehouses · Refunds · Metrics]
        DOCS[Business Documents<br/>Supplier Comms · Support Tickets]
    end

    User --> SUI
    User --> AGT
    AGT --> CAN
    AGT --> CSS
    SUI --> CHN
    SUI --> EVD
    CHN --> CORE
    EVD --> CAI
    EVD --> DOCS
    HST --> CHN
    CAN --> CHN
    CAN --> EVD
```

---

## Snowflake + CoCo Technology

| Technology | Role in PROPAGATE |
|-----------|------------------|
| **Snowflake** | Central data and intelligence layer. All structured events, documents, propagation relationships, evidence, and business metrics are stored and processed in Snowflake. |
| **Cortex Agent** | Natural-language investigation interface over propagation intelligence. Uses Cortex Analyst for text-to-SQL and Cortex Search for document retrieval. |
| **Cortex Analyst + Semantic View** | Structured semantic model (4 logical tables, 9 verified queries) enabling the Agent to query chains, evidence, metrics, and historical data. |
| **Cortex Search** | Hybrid vector + keyword search over the unified document corpus (18 documents, `snowflake-arctic-embed-m-v1.5`). |
| **Cortex AI Functions** | `AI_COMPLETE` for evidence classification, `AI_CLASSIFY` for textual evidence scoring, `SENTIMENT` for document analysis. |
| **Streamlit-in-Snowflake** | Interactive investigation UI — propagation chain visualization, evidence drill-down, historical comparison, and Agent integration. |
| **CoCo CLI** | Development environment used to build, iterate, test, and deploy the entire project within Snowflake. |

---

## Technical Pipeline

```
Structured + unstructured risk signals (CORE + DOCS schemas)
              ↓
       Event normalization (783 events with z-score deviations)
              ↓
     Candidate relationships (214 edges via domain transition graph)
              ↓
     5-component evidence scoring (temporal · structural · magnitude · textual · historical)
              ↓
     Retention threshold (≥ 0.40 → 154 retained edges)
              ↓
     Graph-based forward-walk chain reconstruction (12 chains)
              ↓
     AI document evidence layer (40 evidence records via Cortex AI_COMPLETE)
              ↓
     Contradiction detection + evidence gap identification
              ↓
     Historical comparison across episodes
              ↓
     Cortex Agent + Streamlit investigation
```

The deterministic propagation engine runs entirely in SQL. The LLM enriches and investigates the results — it does not generate the chain structure.

---

## What Makes It Different

| Conventional risk investigation | PROPAGATE |
|--------------------------------|-----------|
| Detects individual anomalies | Traces multi-step risk propagation across business functions |
| Often system-specific | Connects signals across supplier, shipping, warehouse, fulfillment, support, finance |
| Primarily structured signals | Structured events + unstructured document evidence |
| Shows what changed | Investigates how impact propagated |
| Investigation requires manual correlation | Relationships are reconstructed into inspectable chains |
| Evidence may sit in separate systems | Evidence is attached to individual propagation links |
| Focuses on observed impact | Highlights potential earlier detection opportunities |

---

## Historical Pattern Analysis

PROPAGATE compares propagation chains across episodes to identify recurring risk patterns. Three complete chains share the same 6-step supplier-to-revenue structure, with different root causes:

- **September 2026** — port closure (19-day lead, coherence 0.78)
- **July 2026** — equipment failure at origin (14-day lead, coherence 0.77)
- **June 2026** — customs hold (13-day lead, coherence 0.76)

The recurrence suggests a structural vulnerability, but PROPAGATE treats historical similarity as supporting context — not proof that the same cause applies to each instance.

---

## Reliability and Guardrails

- **Ground-truth isolation.** Evaluation tables are never queried by the Streamlit UI, Cortex Agent, or semantic view. Confirmed by automated audit.
- **Structured inference before LLM.** The propagation engine runs entirely in SQL. The LLM enriches relationships with document evidence but does not discover the chain.
- **Evidence per link.** Each edge carries its own structural score, evidence class, and document evidence status.
- **Contradiction surfacing.** 4 contradicting document matches are explicitly displayed, not suppressed.
- **Missing-evidence reporting.** Edges without document evidence display explicit gap indicators.
- **Adversarial testing.** 12 adversarial tests passed, including unrelated-anomaly, temporal-correlation, missing-intermediate, contradiction, generalization, weak-evidence, and anti-hallucination scenarios.
- **Causality discipline.** Every edge carries an evidence class: `CAUSAL_STATED`, `TEXT_SUPPORTED`, `HISTORICAL_SUPPORTED`, or `TEMPORAL_STRUCTURAL` (causation not established).

---

## Evaluation

### Methodology

Evaluation uses deterministic synthetic data with injected ground truth across 3 episodes plus distractors. A 4th challenge episode tests generalization with previously unseen entities. Ground truth is evaluation-only — never read by the inference engine or production UI.

### Original episodes

| Metric | Value |
|--------|-------|
| Chains reconstructed | 3 (all expected) |
| Earliest-signal detection | 3/3 |
| Evidence coverage | 100% of chain edges have ≥2 evidence components |
| False-link rate | 0.7% |

These metrics apply to a controlled synthetic evaluation. They do not represent production-scale performance claims.

### Generalization challenge (unseen entities)

3 of 6 edges were detected; 3 fell below the retention threshold due to cold-start (zero historical/textual evidence for novel entities). The AI evidence layer found strong supporting documents for 2 of those 3 missed edges, but evidence enrichment currently runs after edge retention.

---

## Known Limitations

- **Configured transition graph.** Propagation uses 6 predefined transition types. Novel paths outside this graph cannot be discovered.
- **Cold-start on novel entities.** New entities lack historical recurrence, which can cause legitimate relationships to score below the retention threshold.
- **Document retrieval requires entity overlap.** Documents are matched via shared identifiers and temporal proximity. Purely semantic matches are not yet exploited.
- **Single-document corroboration.** Most chain edges are supported by a single document.
- **Revenue-impact gap.** The refund → revenue transition consistently lacks document evidence because revenue is an aggregated metric.
- **Agent response latency.** Cortex Agent responses take approximately 15–30 seconds.
- **Single-turn Agent.** Each Agent query is stateless.
- **Demonstration domain only.** Fraud and regulatory risk applications are potential extensions, not implemented capabilities.

---

## Demo Flow (3 minutes)

1. **Open PROPAGATE** — default: West-region September 2026
2. **Read the narrative** — "Supplier schedule disruption → West-region revenue impact"
3. **See the key metric** — 19-day earliest detection opportunity
4. **Walk the chain** — 6 steps from supplier to revenue, each with evidence badges
5. **Expand a step** — see the supplier quote: *"port closure... delivery window back by approximately 10 days"*
6. **Historical Comparison** — same pattern in June and July, revenue chart with markers
7. **Ask the Agent** — *"Could we have detected this earlier?"*
8. **Anti-hallucination test** — *"Why did East region revenue decline because of SUP-ACME?"* — confirm refusal to invent
9. **Close** — *"From the first signal to the business impact"*

---

## Repository Structure

```
propagate/
├── README.md
├── .gitignore
├── sql/                            # Phased, idempotent SQL pipeline
│   ├── 01_setup.sql                # Database + schema creation
│   ├── 02_tables.sql               # Table DDL
│   ├── 03_seed.sql                 # Deterministic synthetic data
│   ├── 04_event_spine.sql          # Event normalization
│   ├── 05_candidate_linker.sql     # Candidate relationship generation
│   ├── 06_evidence_scorer.sql      # 5-component evidence scoring
│   ├── 07_chain_builder.sql        # Chain reconstruction v1
│   ├── 08_chain_builder_v2.sql     # Chain reconstruction v2 (production)
│   ├── 09_validation.sql           # Evaluation scorecard
│   ├── 10–12_*.sql                 # Challenge episode + evaluation
│   ├── 13_phase3_evidence_layer.sql # AI document evidence
│   ├── 14_phase4_agent.sql         # Agent + semantic view deployment
│   ├── 15_phase5_streamlit.sql     # Streamlit deployment
│   └── phase*_tests.sql            # Per-phase test suites
├── streamlit/
│   ├── streamlit_app.py            # Investigation UI
│   └── snowflake.yml               # Deployment manifest
├── cortex_project/
│   ├── PROPAGATE_ANALYTICS.sv.yaml # Semantic view
│   ├── PROPAGATE_AGENT.agent.yaml  # Cortex Agent
│   └── cortex-project.yaml         # Deployment manifest
└── docs/                           # Per-phase results and demo script
```

---

## Setup

### Prerequisites

- Snowflake account with Cortex AI, Cortex Search, Cortex Agent, and Streamlit enabled
- Warehouse: `COMPUTE_WH`
- CoCo CLI or Snowsight SQL worksheet

### Deploy

Run SQL scripts in order (each is idempotent):

```
01_setup → 02_tables → 03_seed → 04_event_spine → 05_candidate_linker
→ 06_evidence_scorer → 08_chain_builder_v2 → 09_validation
→ 10–12 (challenge, optional) → 13_phase3_evidence_layer
→ 14_phase4_agent → 15_phase5_streamlit
```

For Streamlit deployment, replace `<REPO>` in `15_phase5_streamlit.sql` with the path to your local clone.

### Access

Open **PROPAGATE.ANALYTICS.PROPAGATE_APP** in Snowsight.

---

## Future Applications

The propagation framework is designed to generalize beyond the current demonstration domain:

**Fraud investigation.** Suspicious transaction signal → account/network activity → exposure spread → financial loss. The same propagation-chain abstraction applies: trace how an early fraud indicator moves through connected entities before becoming measurable loss.

**Regulatory/compliance risk.** Regulatory change or signal → affected process/product → compliance exposure → business/legal impact. Trace how a regulatory development propagates into operational and financial consequences.

**Broader operational risk.** Any domain where an early signal cascades through multiple business functions before becoming visible impact.

These are potential future applications of the same architecture. They are not implemented in the current prototype.

---

PROPAGATE moves risk investigation from *"What changed?"* to *"What started it, how did it propagate, what evidence connects the path, and where could we have detected it earlier?"*

**From the first signal to the business impact.**
