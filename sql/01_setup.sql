-- PROPAGATE :: Phase 1 :: 01_setup.sql
-- Foundation: database + schemas. Idempotent.
-- CoCo-CLI driven; runs in-account, no local deps.

CREATE DATABASE IF NOT EXISTS PROPAGATE;

CREATE SCHEMA IF NOT EXISTS PROPAGATE.CORE;       -- structured business data
CREATE SCHEMA IF NOT EXISTS PROPAGATE.DOCS;       -- unstructured sources (MVP: supplier comms + support tickets)
CREATE SCHEMA IF NOT EXISTS PROPAGATE.ANALYTICS;  -- event spine, edges, chains, ground truth
