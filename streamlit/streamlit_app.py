from snowflake.snowpark.context import get_active_session
import streamlit as st
import pandas as pd
import altair as alt
import json

st.set_page_config(page_title="PROPAGATE", page_icon="🔗", layout="wide")
session = get_active_session()

DB = "PROPAGATE"

CLASS_BADGE = {
    "CAUSAL_STATED": "🟣 Causal — stated",
    "TEXT_SUPPORTED": "🔵 Text — supported",
    "HISTORICAL_SUPPORTED": "🟢 Historical — supported",
    "TEMPORAL_STRUCTURAL": "🟡 Temporal / structural",
    "CORRELATION_ONLY": "⚪ Correlation only",
}
CLASS_COLOR = {
    "CAUSAL_STATED": "#9b59b6",
    "TEXT_SUPPORTED": "#3498db",
    "HISTORICAL_SUPPORTED": "#27ae60",
    "TEMPORAL_STRUCTURAL": "#f39c12",
    "CORRELATION_ONLY": "#95a5a6",
}
DOC_STATUS_BADGE = {
    "STRONGLY_SUPPORTED": "✅ Strongly supported",
    "SUPPORTED": "✅ Supported",
    "WEAK_EVIDENCE": "🔸 Weak evidence",
    "MIXED_EVIDENCE": "⚠️ Mixed evidence",
    "CONTRADICTED": "❌ Contradicted",
    "NO_DOCUMENT_EVIDENCE": "📭 No document evidence",
}


@st.cache_data(ttl=300)
def q(sql: str) -> pd.DataFrame:
    return session.sql(sql).to_pandas()


def fmt_date(ts):
    return pd.to_datetime(ts).strftime("%b %d, %Y") if pd.notna(ts) else "—"


def fmt_datetime(ts):
    return pd.to_datetime(ts).strftime("%b %d %H:%M") if pd.notna(ts) else "—"


def relation_label(r):
    return r.replace("_", " ").replace("PRECEDES", "→").replace("ASSOCIATED WITH", "→").title()


@st.cache_data(ttl=300)
def load_chains():
    return q(f"""
        SELECT CHAIN_ID, ROOT_TYPE, ROOT_TIME, IMPACT_TYPE, IMPACT_TIME, IMPACT_REGION,
               EDGE_COUNT, CHAIN_STATUS, COHERENCE_SCORE, INTERVENTION_LEAD_DAYS,
               INTERVENTION_FUNCTION, EARLIEST_SIGNAL_FUNCTION, EARLIEST_INTERVENTION_EVENT,
               MIN_EDGE_SCORE, AVG_EDGE_SCORE, AFFECTED_ENTITY_COUNT
        FROM {DB}.ANALYTICS.CHAINS ORDER BY COHERENCE_SCORE DESC
    """)


@st.cache_data(ttl=300)
def load_chain_steps(chain_id):
    safe = chain_id.replace("'", "''")
    return q(f"""
        SELECT * FROM {DB}.ANALYTICS.V_CHAIN_INVESTIGATION
        WHERE CHAIN_ID = '{safe}' ORDER BY STEP_NO
    """)


@st.cache_data(ttl=300)
def load_edge_evidence(edge_id, chain_id):
    safe_e = edge_id.replace("'", "''")
    safe_c = chain_id.replace("'", "''")
    return q(f"""
        SELECT * FROM {DB}.ANALYTICS.PROPAGATION_EVIDENCE
        WHERE EDGE_ID = '{safe_e}' AND CHAIN_ID = '{safe_c}'
        ORDER BY evidence_class, relevance_score DESC
    """)


# ═══════════════ SIDEBAR ═══════════════
st.sidebar.markdown("## 🔗 PROPAGATE")
st.sidebar.caption("From the first signal to the business impact")

chains_df = load_chains()
all_chains = chains_df

complete_ids = []
partial_ids = []
chain_labels = {}
for _, r in all_chains.iterrows():
    region = str(r["IMPACT_REGION"]).capitalize()
    root_date = pd.to_datetime(r["ROOT_TIME"])
    month_label = root_date.strftime("%B %Y")
    chain_labels[r["CHAIN_ID"]] = f"{region} — {month_label}"
    if r["CHAIN_STATUS"] == "complete":
        complete_ids.append(r["CHAIN_ID"])
    else:
        partial_ids.append(r["CHAIN_ID"])

default_chain = "CHAIN_SC-G1" if "CHAIN_SC-G1" in complete_ids else (
    complete_ids[0] if complete_ids else list(chain_labels.keys())[0]
)

st.sidebar.markdown("**Investigations**")
selected_chain = st.sidebar.selectbox(
    "Complete chains",
    complete_ids if complete_ids else list(chain_labels.keys()),
    index=complete_ids.index(default_chain) if default_chain in complete_ids else 0,
    format_func=lambda x: chain_labels.get(x, x),
    label_visibility="collapsed",
)
if partial_ids:
    show_partial = st.sidebar.checkbox("Show partial chains", value=False)
    if show_partial:
        partial_sel = st.sidebar.selectbox(
            "Partial chains",
            partial_ids,
            format_func=lambda x: f"{chain_labels.get(x, x)} (partial)",
            label_visibility="collapsed",
        )
        selected_chain = partial_sel

st.sidebar.markdown("---")
page = st.sidebar.radio("View", [
    "Chain Investigation",
    "Evidence Deep-Dive",
    "Historical Comparison",
    "Investigation Agent",
])
st.sidebar.markdown("---")
st.sidebar.caption("**Evidence classes**")
for _k, _v in CLASS_BADGE.items():
    st.sidebar.caption(_v)
st.sidebar.markdown("---")
st.sidebar.caption("Propagation evidence ≠ causal proof")

# ═══════════════ LOAD SELECTED CHAIN ═══════════════
chain_info = all_chains[all_chains["CHAIN_ID"] == selected_chain].iloc[0]
steps = load_chain_steps(selected_chain)

# ═══════════════════════════════════════════════════════
# PAGE 1: CHAIN INVESTIGATION
# ═══════════════════════════════════════════════════════
if page == "Chain Investigation":
    st.markdown(f"# {chain_labels[selected_chain]}")
    st.caption(f"Chain: `{selected_chain}` · {chain_info['CHAIN_STATUS']}")

    # ── Executive summary cards ──
    root_ts = pd.to_datetime(chain_info["ROOT_TIME"])
    impact_ts = pd.to_datetime(chain_info["IMPACT_TIME"])
    lead_days = int(chain_info["INTERVENTION_LEAD_DAYS"])

    c1, c2, c3, c4, c5, c6 = st.columns(6)
    c1.metric("Earliest Signal", fmt_date(chain_info["ROOT_TIME"]),
              help=f"{chain_info['ROOT_TYPE']} ({chain_info['EARLIEST_SIGNAL_FUNCTION']})")
    c2.metric("Intervention Point", fmt_date(chain_info["ROOT_TIME"]),
              help=f"Potential intervention at {chain_info['INTERVENTION_FUNCTION']} function. "
                   "Does not establish that intervention would have prevented the impact.")
    c3.metric("Signal → Impact", f"{lead_days} days",
              help=f"Calendar days (DATEDIFF) from earliest signal "
                   f"({root_ts.strftime('%b %d %H:%M')}) to observed business impact "
                   f"({impact_ts.strftime('%b %d %H:%M')}). "
                   f"Elapsed time: {(impact_ts - root_ts).total_seconds() / 86400:.1f} days.")
    c4.metric("Chain Length", f"{int(chain_info['EDGE_COUNT'])} steps")

    edges_with_evidence = len(steps[steps["DOCUMENT_EVIDENCE_STATUS"] != "NO_DOCUMENT_EVIDENCE"]) if len(steps) else 0
    total_edges = len(steps)
    c5.metric("Evidence Coverage", f"{edges_with_evidence}/{total_edges}",
              help="Chain edges with document evidence")

    gaps = len(steps[steps["DOCUMENT_EVIDENCE_STATUS"] == "NO_DOCUMENT_EVIDENCE"]) if len(steps) else 0
    contradictions = len(steps[steps["CONTRADICTING_DOC_COUNT"] > 0]) if len(steps) else 0
    gap_label = f"{gaps} gaps" if gaps else "None"
    if contradictions:
        gap_label += f", {contradictions} contradicted"
    c6.metric("Evidence Gaps", gap_label)

    st.markdown("---")

    # ── Propagation Timeline ──
    st.subheader("Propagation Timeline")

    if len(steps):
        for _, e in steps.iterrows():
            step_num = int(e["STEP_NO"])
            src_fn = str(e["SOURCE_FUNCTION"])
            tgt_fn = str(e["TARGET_FUNCTION"])
            src_entity = str(e["SOURCE_ENTITY"])
            tgt_entity = str(e["TARGET_ENTITY"])
            src_time = fmt_datetime(e["SOURCE_TIME"])
            tgt_time = fmt_datetime(e["TARGET_TIME"])
            lag = int(e["LAG_DAYS"]) if pd.notna(e["LAG_DAYS"]) else 0
            s_score = float(e["STRUCTURAL_SCORE"]) if pd.notna(e["STRUCTURAL_SCORE"]) else 0
            s_class = str(e["STRUCTURAL_CLASS"])
            doc_status = str(e["DOCUMENT_EVIDENCE_STATUS"])
            sup_count = int(e["SUPPORTING_DOC_COUNT"]) if pd.notna(e["SUPPORTING_DOC_COUNT"]) else 0
            con_count = int(e["CONTRADICTING_DOC_COUNT"]) if pd.notna(e["CONTRADICTING_DOC_COUNT"]) else 0

            badge = CLASS_BADGE.get(s_class, s_class)
            doc_badge = DOC_STATUS_BADGE.get(doc_status, doc_status)
            color = CLASS_COLOR.get(s_class, "#666")

            if step_num == 1:
                st.markdown(f"**{src_time}** · `{src_entity}` · {src_fn}")

            with st.container():
                col_arrow, col_detail = st.columns([1, 11])
                with col_arrow:
                    st.markdown(
                        f"<div style='text-align:center;font-size:1.5em;color:{color}'>↓</div>",
                        unsafe_allow_html=True,
                    )
                with col_detail:
                    st.markdown(
                        f"**Step {step_num}: {src_fn} → {tgt_fn}** &nbsp; "
                        f"{badge} &nbsp; {doc_badge}")
                    dc1, dc2, dc3 = st.columns([2, 2, 2])
                    dc1.caption(f"`{src_entity}` → `{tgt_entity}`")
                    dc2.caption(f"Lag: {lag}d · Score: {s_score:.2f}")
                    dc3.caption(f"Docs: {sup_count} support, {con_count} contradict")

                    snippet_val = e["SUPPORT_SNIPPET"] if "SUPPORT_SNIPPET" in e.index else None
                    if pd.notna(snippet_val) and str(snippet_val) not in ("", "None"):
                        st.caption(f'📄 *"{str(snippet_val)[:120]}..."*')

            st.markdown(f"**{tgt_time}** · `{tgt_entity}` · {tgt_fn}")

        st.markdown("---")

        # ── Timeline chart ──
        st.subheader("Chronological View")
        tl_data = []
        for _, e in steps.iterrows():
            tl_data.append({
                "time": pd.to_datetime(e["SOURCE_TIME"]),
                "function": str(e["SOURCE_FUNCTION"]),
                "entity": str(e["SOURCE_ENTITY"]),
                "step": int(e["STEP_NO"]),
            })
        last_step = steps.iloc[-1]
        tl_data.append({
            "time": pd.to_datetime(last_step["TARGET_TIME"]),
            "function": str(last_step["TARGET_FUNCTION"]),
            "entity": str(last_step["TARGET_ENTITY"]),
            "step": int(last_step["STEP_NO"]) + 1,
        })
        tl_df = pd.DataFrame(tl_data)

        chart = alt.Chart(tl_df).mark_circle(size=250).encode(
            x=alt.X("time:T", title="Date"),
            y=alt.Y("function:N", sort=None, title="Business Function"),
            color=alt.Color("function:N", legend=None),
            tooltip=["step:Q", "function:N", "entity:N", "time:T"],
        ).properties(height=250)
        line = alt.Chart(tl_df).mark_line(strokeDash=[4, 2], opacity=0.4).encode(
            x="time:T", y=alt.Y("function:N", sort=None), order="step:Q",
        )
        st.altair_chart(chart + line, use_container_width=True)
    else:
        st.info("No chain steps found for this selection.")


# ═══════════════════════════════════════════════════════
# PAGE 2: EVIDENCE DEEP-DIVE
# ═══════════════════════════════════════════════════════
elif page == "Evidence Deep-Dive":
    st.markdown(f"# Evidence: {chain_labels[selected_chain]}")

    if len(steps) == 0:
        st.info("No chain steps found.")
    else:
        step_options = steps["STEP_NO"].tolist()
        step_labels_map = {
            int(r["STEP_NO"]): f"Step {int(r['STEP_NO'])}: {r['SOURCE_FUNCTION']} → {r['TARGET_FUNCTION']}"
            for _, r in steps.iterrows()
        }
        selected_step = st.selectbox(
            "Select edge",
            step_options,
            format_func=lambda s: step_labels_map.get(int(s), f"Step {s}"),
        )

        e = steps[steps["STEP_NO"] == selected_step].iloc[0]

        # ── Structural evidence ──
        st.subheader("Structured Evidence")
        s1, s2, s3, s4 = st.columns(4)
        s1.metric("Source", f"{e['SOURCE_ENTITY']}", help=str(e["SOURCE_EVENT_TYPE"]))
        s2.metric("Target", f"{e['TARGET_ENTITY']}", help=str(e["TARGET_EVENT_TYPE"]))
        s3.metric("Time Delta", f"{int(e['LAG_DAYS'])} days")
        s4.metric("Structural Score", f"{float(e['STRUCTURAL_SCORE']):.3f}")

        st.markdown(f"**Relationship**: {relation_label(str(e['RELATION']))}")
        st.markdown(f"**Evidence class**: {CLASS_BADGE.get(str(e['STRUCTURAL_CLASS']), str(e['STRUCTURAL_CLASS']))}")
        st.markdown(f"**Document status**: {DOC_STATUS_BADGE.get(str(e['DOCUMENT_EVIDENCE_STATUS']), str(e['DOCUMENT_EVIDENCE_STATUS']))}")

        st.markdown("---")

        # ── Document evidence ──
        st.subheader("Document Evidence")
        evidence = load_edge_evidence(str(e["EDGE_ID"]), selected_chain)

        if len(evidence) == 0:
            st.warning(
                "**📭 No document evidence found.** "
                "This edge is supported by structured operational data only "
                "(temporal precedence, entity overlap, historical recurrence)."
            )
        else:
            supports = evidence[evidence["EVIDENCE_CLASS"] == "SUPPORTS"]
            contradicts = evidence[evidence["EVIDENCE_CLASS"] == "CONTRADICTS"]
            context = evidence[evidence["EVIDENCE_CLASS"] == "CONTEXT"]

            if len(supports):
                st.markdown("**Supporting documents**")
                for _, d in supports.iterrows():
                    with st.container():
                        strength = str(d.get("EVIDENCE_STRENGTH", ""))
                        st.markdown(f"📄 **{d['DOCUMENT_ID']}** ({d['DOCUMENT_TYPE']}) — {strength}")
                        st.caption(
                            f"Entity match: {d.get('ENTITY_MATCH_SCORE', 0):.1f} · "
                            f"Temporal match: {d.get('TEMPORAL_MATCH_SCORE', 0):.1f} · "
                            f"Relevance: {d.get('RELEVANCE_SCORE', 0):.2f}"
                        )
                        snippet = str(d.get("EVIDENCE_SNIPPET", ""))
                        if snippet and snippet != "None":
                            st.info(f'"{snippet}"')
                        summary = str(d.get("EVIDENCE_SUMMARY", ""))
                        if summary and summary != "None":
                            st.caption(summary)

            if len(contradicts):
                st.markdown("**⚠ Contradictory documents**")
                for _, d in contradicts.iterrows():
                    with st.container():
                        st.markdown(f"❌ **{d['DOCUMENT_ID']}** ({d['DOCUMENT_TYPE']})")
                        snippet = str(d.get("EVIDENCE_SNIPPET", ""))
                        if snippet and snippet != "None":
                            st.error(f'"{snippet}"')
                        summary = str(d.get("EVIDENCE_SUMMARY", ""))
                        if summary and summary != "None":
                            st.caption(summary)

            if len(context):
                with st.expander(f"Context documents ({len(context)})"):
                    for _, d in context.iterrows():
                        st.caption(f"📋 {d['DOCUMENT_ID']} ({d['DOCUMENT_TYPE']})")
                        snippet = str(d.get("EVIDENCE_SNIPPET", ""))
                        if snippet and snippet != "None":
                            st.caption(f'"{snippet}"')


# ═══════════════════════════════════════════════════════
# PAGE 3: HISTORICAL COMPARISON
# ═══════════════════════════════════════════════════════
elif page == "Historical Comparison":
    st.markdown("# Have We Seen This Before?")
    st.caption("Historical recurrence is itself evidence — the HISTORICAL_SUPPORTED evidence class.")

    complete = all_chains[all_chains["CHAIN_STATUS"] == "complete"].copy()
    if len(complete) == 0:
        st.info("No complete propagation chains found for comparison.")
    else:
        complete["ROOT_DATE"] = pd.to_datetime(complete["ROOT_TIME"]).dt.date
        complete["IMPACT_DATE"] = pd.to_datetime(complete["IMPACT_TIME"]).dt.date

        current = complete[complete["CHAIN_ID"] == selected_chain]
        historical = complete[complete["CHAIN_ID"] != selected_chain]

        if len(current) == 0:
            st.info(f"Selected chain `{selected_chain}` is partial. "
                    "Showing all complete chains for reference.")
            display_chains = complete
        else:
            cur = current.iloc[0]
            st.markdown(f"### Current: {chain_labels.get(selected_chain, selected_chain)}")
            cc1, cc2, cc3, cc4 = st.columns(4)
            cc1.metric("Root", fmt_date(cur["ROOT_TIME"]))
            cc2.metric("Impact", fmt_date(cur["IMPACT_TIME"]))
            cc3.metric("Signal → Impact", f"{int(cur['INTERVENTION_LEAD_DAYS'])} days")
            cc4.metric("Coherence", f"{cur['COHERENCE_SCORE']:.3f}")
            display_chains = historical

        if len(display_chains) == 0:
            st.info("No other complete chains found for comparison.")
        else:
            st.markdown("### Historical Episodes")
            for _, h in display_chains.iterrows():
                with st.container():
                    hc1, hc2, hc3, hc4, hc5 = st.columns(5)
                    hc1.markdown(f"**{chain_labels.get(h['CHAIN_ID'], h['CHAIN_ID'])}**")
                    hc2.caption(f"Root: {fmt_date(h['ROOT_TIME'])}")
                    hc3.caption(f"Impact: {fmt_date(h['IMPACT_TIME'])}")
                    hc4.caption(f"Lead: {int(h['INTERVENTION_LEAD_DAYS'])}d")
                    hc5.caption(f"Coherence: {h['COHERENCE_SCORE']:.3f}")

            # ── Structural comparison ──
            if len(current) > 0:
                cur = current.iloc[0]
                same_root = complete[complete["ROOT_TYPE"] == str(cur["ROOT_TYPE"])]
                if len(same_root) > 1:
                    st.markdown("### Pattern Comparison")
                    st.markdown(
                        f"**{len(same_root)} chains** share the same root type "
                        f"(`{cur['ROOT_TYPE']}`) and reach revenue impact."
                    )
                    cmp_df = same_root[["CHAIN_ID", "ROOT_DATE", "IMPACT_DATE", "IMPACT_REGION",
                                        "EDGE_COUNT", "COHERENCE_SCORE", "INTERVENTION_LEAD_DAYS"]].copy()
                    cmp_df.columns = ["Chain", "Root Date", "Impact Date", "Region",
                                      "Steps", "Coherence", "Lead Days"]
                    st.dataframe(cmp_df, use_container_width=True, hide_index=True)

        # ── Revenue chart ──
        st.markdown("### West Region Revenue")
        rev = q(f"""SELECT metric_date, revenue FROM {DB}.CORE.BUSINESS_METRICS
                    WHERE region='west' ORDER BY metric_date""")
        rev["METRIC_DATE"] = pd.to_datetime(rev["METRIC_DATE"])

        root_dates = complete[complete["IMPACT_REGION"] == "west"]["ROOT_TIME"].apply(
            pd.to_datetime
        ).tolist()
        rev_chart = alt.Chart(rev).mark_area(opacity=0.3).encode(
            x=alt.X("METRIC_DATE:T", title="Date"),
            y=alt.Y("REVENUE:Q", title="Daily Revenue ($)"),
        )
        line_chart = alt.Chart(rev).mark_line(color="#2c3e50").encode(
            x="METRIC_DATE:T", y="REVENUE:Q",
        )
        if root_dates:
            rules_data = pd.DataFrame({"date": root_dates})
            rules = alt.Chart(rules_data).mark_rule(
                color="red", strokeDash=[4, 2]
            ).encode(x="date:T")
            st.altair_chart(rev_chart + line_chart + rules, use_container_width=True)
        else:
            st.altair_chart(rev_chart + line_chart, use_container_width=True)
        st.caption("Red dashed lines = chain root dates. Each dip aligns with a reconstructed propagation chain.")


# ═══════════════════════════════════════════════════════
# PAGE 4: INVESTIGATION AGENT
# ═══════════════════════════════════════════════════════
elif page == "Investigation Agent":
    st.markdown("# Investigate This Chain")
    st.caption(
        "Ask the PROPAGATE Cortex Agent about the propagation intelligence. "
        "The Agent queries the same analytical data — it does not invent relationships."
    )

    suggested = [
        "Why did West-region revenue decline in September 2026?",
        "What started the problem?",
        "What evidence supports the shipment delay to warehouse backlog link?",
        "Was there contradictory evidence?",
        "Could we have detected this earlier?",
        "Have we seen something similar before?",
        "Which part of the chain has the weakest evidence?",
        "What evidence is missing?",
    ]

    st.markdown("**Suggested questions:**")
    sg_cols = st.columns(2)
    for i, sq in enumerate(suggested):
        sg_cols[i % 2].caption(f"• {sq}")

    user_query = st.text_input("Ask a question", placeholder="Why did West-region revenue decline?")

    if user_query:
        with st.spinner("Investigating evidence across the propagation chain..."):
            safe_query = user_query.replace("\\", "\\\\").replace('"', '\\"').replace("'", "\\'")
            try:
                result = session.sql(f"""
                    SELECT TRY_PARSE_JSON(
                        SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
                            '{DB}.ANALYTICS.PROPAGATE_AGENT',
                            '{{"messages": [{{"role": "user", "content": [{{"type": "text", "text": "{safe_query}"}}]}}]}}'
                        )
                    ) AS resp
                """).to_pandas()
                resp = result.iloc[0]["RESP"]

                if isinstance(resp, str):
                    parsed = json.loads(resp)
                else:
                    parsed = resp

                if isinstance(parsed, dict) and "content" in parsed:
                    text_parts = [
                        c.get("text", "") for c in parsed["content"]
                        if isinstance(c, dict) and c.get("type") == "text" and c.get("text")
                    ]
                    if text_parts:
                        for part in text_parts:
                            st.markdown(part)
                    else:
                        st.info("The Agent did not return a text response for this query.")
                elif isinstance(parsed, dict) and "message" in parsed:
                    st.error(f"Agent error: {parsed['message']}")
                else:
                    st.write(parsed)
            except Exception as ex:
                st.error(f"Agent query failed: {ex}")
                st.caption(
                    "The Cortex Agent may not be available in this environment. "
                    "Try the question in Snowflake Intelligence instead."
                )

    st.markdown("---")
    st.caption(
        "The PROPAGATE Agent operates over the existing propagation intelligence. "
        "It does not independently discover or invent propagation relationships. "
        "Evidence-backed propagation ≠ causal proof."
    )
