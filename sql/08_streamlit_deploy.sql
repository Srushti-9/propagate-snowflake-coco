-- PROPAGATE :: Phase 7 :: 08_streamlit_deploy.sql
-- Deploys the Streamlit-in-Snowflake app from stage. Reproducible via pure SQL + PUT
-- (no local snow/uv CLI needed). Re-run after editing streamlit/streamlit_app.py.

CREATE STAGE IF NOT EXISTS PROPAGATE.ANALYTICS.APP_STAGE DIRECTORY = (ENABLE = TRUE);

-- Upload the app file (run from a client that supports PUT; path is the repo copy):
PUT 'file://<REPO>/streamlit/streamlit_app.py' @PROPAGATE.ANALYTICS.APP_STAGE
    AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

CREATE OR REPLACE STREAMLIT PROPAGATE.ANALYTICS.PROPAGATE_APP
  ROOT_LOCATION = '@PROPAGATE.ANALYTICS.APP_STAGE'
  MAIN_FILE = 'streamlit_app.py'
  QUERY_WAREHOUSE = COMPUTE_WH
  TITLE = 'PROPAGATE';

SHOW STREAMLITS LIKE 'PROPAGATE_APP' IN SCHEMA PROPAGATE.ANALYTICS;
