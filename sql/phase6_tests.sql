-- PROPAGATE :: Phase 6 :: phase6_tests.sql
-- Verifies the AI layer objects exist and are wired. End-to-end NL answer is validated
-- separately via `cortex agents run` (see docs/phase6_results.md for the captured transcript).
-- NOTE: run the SHOW+RESULT_SCAN pairs ONE AT A TIME. Running them concurrently causes
-- LAST_QUERY_ID() collisions (observed during Phase 6 build).

-- 1) analytics views present (expect 2)
SELECT COUNT(*) AS views_present
FROM PROPAGATE.INFORMATION_SCHEMA.VIEWS
WHERE table_schema='ANALYTICS' AND table_name IN ('V_CHAIN_DETAIL','V_CHAIN_SUMMARY');

-- 2) semantic view present (expect 1)
SHOW SEMANTIC VIEWS IN SCHEMA PROPAGATE.ANALYTICS;
SELECT COUNT(*) AS semantic_view_present FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "name"='PROPAGATE_ANALYTICS';

-- 3) Cortex Search service present (expect 1)
SHOW CORTEX SEARCH SERVICES IN SCHEMA PROPAGATE.DOCS;
SELECT COUNT(*) AS search_service_present FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "name"='DOC_SEARCH';

-- 4) Cortex Agent present (expect 1)
SHOW AGENTS LIKE 'PROPAGATE_AGENT' IN SCHEMA PROPAGATE.ANALYTICS;
SELECT COUNT(*) AS agent_present FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "name"='PROPAGATE_AGENT';

-- 5) Cortex Analyst grounds on the semantic view (smoke test, run via CLI):
--    cortex analyst query "Which propagation chain had the longest intervention lead time?" \
--      --view=PROPAGATE.ANALYTICS.PROPAGATE_ANALYTICS
