# EHR Data Pipeline & Analysis

An end-to-end pipeline that sources, structures, validates, and analyzes
clinical data — built as a portfolio project to demonstrate the core skills
of a data analyst working with healthcare data: dataset development, data
quality/anomaly detection, SQL analysis, and algorithm evaluation. Uses
synthetic EHR data (Synthea) in place of real patient data.

## Pipeline

**Synthea (synthetic FHIR data) → S3 (raw storage) → Postgres/RDS (structured
schema) → SQL analysis → QC/anomaly detection → algorithm evaluation
simulation → stakeholder write-up.**

## Stack

Python (boto3, psycopg2) · PostgreSQL (AWS RDS) · AWS S3 · SQL (CTEs, window
functions, JOINs) · Synthea (synthetic FHIR data generator)

## What's in this repo

- `etl_fhir_to_postgres.py` — pulls FHIR bundles from S3, parses Patient,
  Encounter, Condition, Observation, and Procedure resources, resolves FHIR
  references into foreign keys, and loads into Postgres
- `schema.sql` / `schema_diagram.md` — relational schema (5 tables) and an
  ERD (Mermaid)
- `queries/` — analyst SQL queries (cohort definitions, CTE-based joins,
  window-function metrics), each with a comment header explaining the goal
  and any data-quality findings uncovered while building it

## Data quality findings

Two real ETL bugs were found and fixed while exploring the data:
1. **Nested FHIR components dropped** — panel-type observations (e.g. blood
   pressure) store real values in a nested `component` array, not on the
   parent resource. This silently dropped all systolic/diastolic readings.
2. **Patient race/ethnicity misparsed** — the original code assumed a flat,
   fixed-position extension structure that didn't match Synthea's actual
   (nested, URL-keyed) FHIR extension format, resulting in `NULL` for every
   patient.

Both are documented in `queries/` and were caught by cross-referencing
Postgres query results against the raw FHIR JSON.

## Status

Work in progress — see commit history for current phase.
