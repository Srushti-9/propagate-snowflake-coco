-- PROPAGATE :: Phase 5 :: 15_phase5_streamlit.sql
-- Deploys the updated Streamlit investigation product.
--
-- Prerequisites: Phase 1-4 objects must exist.
-- Creates: PROPAGATE.ANALYTICS.PROPAGATE_APP (Streamlit)

CREATE STAGE IF NOT EXISTS PROPAGATE.ANALYTICS.STREAMLIT_STAGE
  DIRECTORY = (ENABLE = TRUE)
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');

PUT 'file:///Users/srushti/Development/Hackathon/Snowflake/propagate/streamlit/streamlit_app.py'
  @PROPAGATE.ANALYTICS.STREAMLIT_STAGE OVERWRITE=TRUE AUTO_COMPRESS=FALSE;

CREATE OR REPLACE STREAMLIT PROPAGATE.ANALYTICS.PROPAGATE_APP
  ROOT_LOCATION = '@PROPAGATE.ANALYTICS.STREAMLIT_STAGE'
  MAIN_FILE = 'streamlit_app.py'
  QUERY_WAREHOUSE = 'COMPUTE_WH'
  TITLE = 'PROPAGATE'
  COMMENT = 'PROPAGATE: Supply-chain propagation investigation';
