from snowflake.snowpark.context import get_active_session
import streamlit as st
import pandas as pd
import altair as alt

st.set_page_config(page_title="PROPAGATE", page_icon="🔗", layout="wide")
session = get_active_session()

DB = "PROPAGATE"

CLASS_BADGE = {
    "CAUSAL_STATED": "🟣 CAUSAL_STATED",
    "TEXT_SUPPORTED": "🔵 TEXT_SUPPORTED",
    "HISTORICAL_SUPPORTED": "🟢 HISTORICAL_SUPPORTED",
    "TEMPORAL_STRUCTURAL": "🟡 TEMPORAL_STRUCTURAL",
    "CORRELATION_ONLY": "⚪ CORRELATION_ONLY",
}
CLASS_HELP = {
    "CAUSAL_STATED": "A document explicitly states the cause. Strongest claim.",
    "TEXT_SUPPORTED": "A document supports the link.",
    "HISTORICAL_SUPPORTED": "The relationship recurs in prior periods.",
    "TEMPORAL_STRUCTURAL": "Only timing + shared entity. Causation NOT established.",
    "CORRELATION_ONLY": "Weakest. Causation NOT established.",
}


@st.cache_data(ttl=300)
def q(sql: str) -> pd.DataFrame:
    return session.sql(sql).to_pandas()


def causality_note(classes):
    strong = {"CAUSAL_STATED", "TEXT_SUPPORTED"}
    if not any(c in strong for c in classes):
        return ("warning", "No link in this chain has document-level causal evidence. "
                "Treat the end-to-end relationship as temporal/structural — causation is NOT established.")
    if "CAUSAL_STATED" not in classes:
        return ("info", "Links are document- or history-supported, but no explicit causal statement exists. "
                "End-to-end attribution remains inferred, not proven.")
    return ("info", "The root link is explicitly stated as causal in a source document. "
            "Downstream links are supported by text/history/structure — not independently proven causal.")


st.sidebar.title("🔗 PROPAGATE")
st.sidebar.caption("From the first signal to the business impact")
page = st.sidebar.radio("Investigate", [
    "1 · Propagation Overview",
    "2 · Chain Investigation",
    "3 · Evidence Inspection",
    "4 · Historical Comparison",
    "5 · Natural-Language Investigation",
])
st.sidebar.markdown("---")
st.sidebar.caption("Evidence classes")
for k, v in CLASS_BADGE.items():
    st.sidebar.caption(v)


# ---------------- 1. OVERVIEW ----------------
if page.startswith("1"):
    st.title("Propagation Overview")
    s = q(f"SELECT * FROM {DB}.ANALYTICS.V_CHAIN_SUMMARY ORDER BY total_score DESC")
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Propagation chains", len(s))
    c2.metric("Max intervention lead", f"{int(s['INTERVENTION_LEAD_DAYS'].max())} days" if len(s) else "—")
    c3.metric("Affected entities (max)", int(s["AFFECTED_ENTITY_COUNT"].max()) if len(s) else 0)
    c4.metric("Avg chain evidence", f"{s['AVG_EDGE_SCORE'].mean():.2f}" if len(s) else "—")
    st.markdown("Each row is a reconstructed chain from an **earliest signal** to a **business impact**.")
    for _, r in s.iterrows():
        with st.container(border=True):
            a, b = st.columns([3, 1])
            a.markdown(f"### {r['CHAIN_ID']}")
            a.write(f"**{r['ROOT_TYPE']}** ({r['EARLIEST_SIGNAL_FUNCTION']}) "
                    f"on {pd.to_datetime(r['ROOT_TIME']).date()} → "
                    f"**{r['IMPACT_TYPE']}** in *{r['IMPACT_REGION']}* "
                    f"on {pd.to_datetime(r['IMPACT_TIME']).date()}")
            a.caption(f"{r['NODE_COUNT']} nodes · {r['AFFECTED_ENTITY_COUNT']} affected entities "
                      f"· total evidence {r['TOTAL_SCORE']:.2f}")
            b.metric("Lead time", f"{int(r['INTERVENTION_LEAD_DAYS'])} d")
            b.caption(f"Intervene @ {r['INTERVENTION_FUNCTION']}")


# ---------------- 2. CHAIN INVESTIGATION ----------------
elif page.startswith("2"):
    st.title("Chain Investigation")
    chains = q(f"SELECT chain_id FROM {DB}.ANALYTICS.V_CHAIN_SUMMARY ORDER BY total_score DESC")["CHAIN_ID"].tolist()
    chain = st.selectbox("Chain", chains)
    summ = q(f"SELECT * FROM {DB}.ANALYTICS.V_CHAIN_SUMMARY WHERE chain_id='{chain}'").iloc[0]
    det = q(f"SELECT * FROM {DB}.ANALYTICS.V_CHAIN_DETAIL WHERE chain_id='{chain}' ORDER BY step_no")

    c1, c2, c3 = st.columns(3)
    c1.metric("Earliest signal", str(summ["ROOT_TYPE"]), help=str(summ["ROOT_EVENT"]))
    c2.metric("Business impact", str(summ["IMPACT_TYPE"]), help=str(summ["IMPACT_EVENT"]))
    c3.metric("Intervention lead", f"{int(summ['INTERVENTION_LEAD_DAYS'])} days",
              help=f"Earliest observable + actionable point: {summ['INTERVENTION_FUNCTION']}")

    level, msg = causality_note(set(det["EVIDENCE_CLASS"]))
    (st.warning if level == "warning" else st.info)(msg)

    st.subheader("Propagation path")
    for _, e in det.iterrows():
        with st.container(border=True):
            st.markdown(
                f"**Step {int(e['STEP_NO'])} · {e['FROM_FUNCTION']} → {e['TO_FUNCTION']}**  "
                f"&nbsp; {CLASS_BADGE.get(e['EVIDENCE_CLASS'], e['EVIDENCE_CLASS'])}")
            st.write(f"`{e['FROM_ENTITY']}` → `{e['TO_ENTITY']}` &nbsp;·&nbsp; "
                     f"{e['RELATION'].replace('_',' ').lower()}")
            st.caption(f"lag {int(e['LAG_DAYS'])} d · evidence score {e['EVIDENCE_SCORE']:.2f} · "
                       f"{CLASS_HELP.get(e['EVIDENCE_CLASS'],'')}")

    st.subheader("Timeline")
    tl = det[["STEP_NO", "FROM_TIME", "FROM_FUNCTION"]].copy()
    tl["FROM_TIME"] = pd.to_datetime(tl["FROM_TIME"])
    chart = alt.Chart(tl).mark_circle(size=200).encode(
        x="FROM_TIME:T", y=alt.Y("FROM_FUNCTION:N", sort=None), tooltip=["STEP_NO", "FROM_FUNCTION", "FROM_TIME"]
    )
    st.altair_chart(chart, use_container_width=True)


# ---------------- 3. EVIDENCE INSPECTION ----------------
elif page.startswith("3"):
    st.title("Evidence Inspection")
    chains = q(f"SELECT chain_id FROM {DB}.ANALYTICS.V_CHAIN_SUMMARY ORDER BY total_score DESC")["CHAIN_ID"].tolist()
    chain = st.selectbox("Chain", chains)
    edges = q(f"""SELECT ce.step_no, ce.relation, ce.from_event, ce.to_event, se.*
                  FROM {DB}.ANALYTICS.CHAIN_EDGES ce
                  JOIN {DB}.ANALYTICS.SCORED_EDGES se ON se.edge_id = ce.edge_id
                  WHERE ce.chain_id='{chain}' ORDER BY ce.step_no""")
    step = st.selectbox("Step", edges["STEP_NO"].tolist(),
                        format_func=lambda s: f"Step {int(s)} · {edges[edges.STEP_NO==s].iloc[0]['RELATION']}")
    e = edges[edges.STEP_NO == step].iloc[0]

    st.markdown(f"### {CLASS_BADGE.get(e['EVIDENCE_CLASS'], e['EVIDENCE_CLASS'])}  "
                f"— composite score **{e['EVIDENCE_SCORE']:.2f}**")
    st.caption(CLASS_HELP.get(e["EVIDENCE_CLASS"], ""))

    comps = pd.DataFrame({
        "component": ["temporal", "structural", "magnitude", "textual", "historical"],
        "score": [e["COMP_TEMPORAL"], e["COMP_STRUCTURAL"], e["COMP_MAGNITUDE"], e["COMP_TEXTUAL"], e["COMP_HISTORICAL"]],
    })
    st.altair_chart(
        alt.Chart(comps).mark_bar().encode(
            x=alt.X("score:Q", scale=alt.Scale(domain=[0, 1])),
            y=alt.Y("component:N", sort=None), tooltip=["component", "score"]),
        use_container_width=True)

    st.subheader("Source evidence")
    docs = q(f"""SELECT doc_id, doc_type, entity_ref, event_time, body_text
                 FROM {DB}.DOCS.V_ALL_DOCS
                 WHERE doc_id IN (
                   SELECT text_ref FROM {DB}.ANALYTICS.EVENT_LOG
                   WHERE event_id IN ('{e['FROM_EVENT']}','{e['TO_EVENT']}') AND text_ref IS NOT NULL)""")
    if len(docs):
        for _, d in docs.iterrows():
            with st.container(border=True):
                st.caption(f"{d['DOC_TYPE']} · {d['DOC_ID']} · {d['ENTITY_REF']} · {pd.to_datetime(d['EVENT_TIME']).date()}")
                st.write(d["BODY_TEXT"])
    else:
        st.caption("No document attached to this edge — evidence is temporal/structural/historical only.")


# ---------------- 4. HISTORICAL COMPARISON ----------------
elif page.startswith("4"):
    st.title("Historical Comparison")
    s = q(f"SELECT * FROM {DB}.ANALYTICS.V_CHAIN_SUMMARY ORDER BY root_time")
    st.markdown("The same supplier → revenue pattern recurs. Recurrence is itself evidence "
                "(the `HISTORICAL_SUPPORTED` class).")
    show = s[["CHAIN_ID", "ROOT_TIME", "IMPACT_TIME", "IMPACT_REGION", "NODE_COUNT",
              "TOTAL_SCORE", "INTERVENTION_LEAD_DAYS"]].copy()
    show["ROOT_TIME"] = pd.to_datetime(show["ROOT_TIME"]).dt.date
    show["IMPACT_TIME"] = pd.to_datetime(show["IMPACT_TIME"]).dt.date
    st.dataframe(show, use_container_width=True, hide_index=True)

    st.subheader("West region revenue — baseline vs dips")
    rev = q(f"""SELECT metric_date, revenue FROM {DB}.CORE.BUSINESS_METRICS
                WHERE region='west' ORDER BY metric_date""")
    rev["METRIC_DATE"] = pd.to_datetime(rev["METRIC_DATE"])
    st.altair_chart(
        alt.Chart(rev).mark_line().encode(x="METRIC_DATE:T", y="REVENUE:Q", tooltip=["METRIC_DATE", "REVENUE"]),
        use_container_width=True)
    st.caption("Each dip aligns with a reconstructed chain rooted at a SUP-ACME schedule change.")


# ---------------- 5. NL INVESTIGATION ----------------
else:
    st.title("Natural-Language Investigation")
    st.caption("Grounded in Cortex Search (document evidence) + the propagation chains. "
               "The full PROPAGATE Cortex Agent is also available in Snowflake Intelligence.")
    default = "late delivery refund complaint west region"
    query = st.text_input("Ask about an incident / search the evidence", value=default)
    if query:
        st.subheader("Document evidence (Cortex Search)")
        safe = query.replace("'", "''")
        res = q(f"""SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
                      '{DB}.DOCS.DOC_SEARCH',
                      '{{"query":"{safe}","columns":["doc_id","doc_type","entity_ref","body_text"],"limit":4}}'
                    )):results AS r""")
        import json
        rows = json.loads(res.iloc[0]["R"]) if len(res) and res.iloc[0]["R"] else []
        for d in rows:
            with st.container(border=True):
                st.caption(f"{d.get('doc_type')} · {d.get('doc_id')} · {d.get('entity_ref')}")
                st.write(d.get("body_text"))

        st.subheader("Grounded summary (Cortex AI)")
        ctx = "; ".join(f"{d.get('doc_type')} {d.get('doc_id')}: {d.get('body_text')}" for d in rows)
        prompt = ("You are a supply-chain propagation analyst. Using ONLY the evidence below, "
                  "briefly explain what likely happened and name the earliest signal. Do NOT claim "
                  "causation unless a document explicitly states a cause; otherwise say the relationship "
                  f"is temporal/structural only. Evidence: {ctx}").replace("'", "''")
        ans = q(f"SELECT SNOWFLAKE.CORTEX.COMPLETE('llama3.1-8b','{prompt}') AS a")
        st.write(ans.iloc[0]["A"])
