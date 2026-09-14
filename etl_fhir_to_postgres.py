"""
ETL: Synthea FHIR bundles (S3) -> Postgres/RDS relational schema

Reads each FHIR bundle JSON from S3, extracts Patient, Encounter, Condition,
Observation, and Procedure resources, resolves internal FHIR references into
foreign keys, and batch-inserts into the corresponding Postgres tables.

Usage:
    python3 etl_fhir_to_postgres.py
"""

import boto3
import json
import psycopg2
import uuid
from psycopg2.extras import execute_values

import dotenv
dotenv.load_dotenv()  # load DB_PASSWORD from .env if present

# ---------------------------------------------------------------------------
# Config — edit these to match your environment
# ---------------------------------------------------------------------------
S3_BUCKET = "guy-ilan-aidoc-ehr-pipeline"
S3_PREFIX = "raw-fhir-bundles/"

DB_HOST = "aidoc-ehr-pipeline.c0rumk4uq6lj.us-east-1.rds.amazonaws.com"
DB_PORT = 5432
DB_NAME = "aidoc_ehr"
DB_USER = "ehradmin"
DB_PASSWORD = dotenv.dotenv_values().get("DB_PASSWORD")  # set your RDS master password here, or load from env

RACE_EXT_URL = "http://hl7.org/fhir/us/core/StructureDefinition/us-core-race"
ETHNICITY_EXT_URL = "http://hl7.org/fhir/us/core/StructureDefinition/us-core-ethnicity"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
 
def ref_id(reference):
    """FHIR references look like 'Patient/abc-123' or 'urn:uuid:abc-123'.
    Extract just the UUID part."""
    if not reference:
        return None
    return reference.split("/")[-1].replace("urn:uuid:", "")
 
 
def get_coding(resource, field="code"):
    """Pull the first coding's code + display text from a CodeableConcept field."""
    concept = resource.get(field, {})
    codings = concept.get("coding", [])
    code = codings[0].get("code") if codings else None
    description = concept.get("text") or (codings[0].get("display") if codings else None)
    return code, description
 
 
def get_value(node):
    """Pull a scalar value + unit off any FHIR node that carries value[x]
    (works for both a top-level Observation and a component sub-object)."""
    value, unit = None, None
    if "valueQuantity" in node:
        value = str(node["valueQuantity"].get("value"))
        unit = node["valueQuantity"].get("unit")
    elif "valueString" in node:
        value = node["valueString"]
    elif "valueCodeableConcept" in node:
        value = node["valueCodeableConcept"].get("text")
    return value, unit
 
 
def get_us_core_category_text(patient_resource, extension_url):
    """Extract the US Core race/ethnicity extension value.
 
    Shape:
        { "url": <extension_url>,
          "extension": [
              {"url": "ombCategory", "valueCoding": {"display": "White", ...}},
              {"url": "text", "valueString": "White"}
          ] }
 
    Matches by URL (not position) since extension order/presence varies by
    patient (e.g. multi-race patients can have multiple ombCategory entries).
    """
    for ext in patient_resource.get("extension", []):
        if ext.get("url") != extension_url:
            continue
        sub_exts = ext.get("extension", [])
        # Prefer the human-readable "text" sub-extension.
        for sub in sub_exts:
            if sub.get("url") == "text" and "valueString" in sub:
                return sub["valueString"]
        # Fall back to the first ombCategory coding's display text.
        for sub in sub_exts:
            if sub.get("url") == "ombCategory" and "valueCoding" in sub:
                return sub["valueCoding"].get("display")
    return None
 
 
def parse_bundle(bundle):
    """Split one FHIR bundle into rows per table."""
    patients, encounters, conditions, observations, procedures = [], [], [], [], []
 
    for entry in bundle.get("entry", []):
        resource = entry.get("resource", {})
        rtype = resource.get("resourceType")
 
        if rtype == "Patient":
            pid = resource.get("id")
            name = resource.get("name", [{}])[0]
            address = resource.get("address", [{}])[0]
            race = get_us_core_category_text(resource, RACE_EXT_URL)
            ethnicity = get_us_core_category_text(resource, ETHNICITY_EXT_URL)
            patients.append((
                pid,
                resource.get("birthDate"),
                resource.get("gender"),
                race,
                ethnicity,
                " ".join(name.get("given", [])),
                name.get("family"),
                " ".join(address.get("line", [])),
                address.get("city"),
                address.get("state"),
                address.get("postalCode"),
            ))
 
        elif rtype == "Encounter":
            period = resource.get("period", {})
            reason = (resource.get("reasonCode") or [{}])[0]
            reason_coding = (reason.get("coding") or [{}])
            encounters.append((
                resource.get("id"),
                ref_id(resource.get("subject", {}).get("reference")),
                (resource.get("type") or [{}])[0].get("text"),
                resource.get("class", {}).get("code"),
                period.get("start"),
                period.get("end"),
                reason_coding[0].get("code") if reason_coding else None,
                reason.get("text"),
                None,  # provider_id — would need Practitioner resource lookup
                None,  # organization_id — would need Organization resource lookup
            ))
 
        elif rtype == "Condition":
            code, description = get_coding(resource, "code")
            conditions.append((
                resource.get("id"),
                ref_id(resource.get("subject", {}).get("reference")),
                ref_id(resource.get("encounter", {}).get("reference")),
                code,
                description,
                resource.get("onsetDateTime"),
                resource.get("abatementDateTime"),
                resource.get("clinicalStatus", {}).get("coding", [{}])[0].get("code"),
            ))
 
        elif rtype == "Observation":
            category = (resource.get("category") or [{}])[0].get("coding", [{}])[0].get("code")
            patient_id = ref_id(resource.get("subject", {}).get("reference"))
            encounter_id = ref_id(resource.get("encounter", {}).get("reference"))
            observed_at = resource.get("effectiveDateTime")
            parent_id = resource.get("id")
 
            components = resource.get("component")
            if components:
                # Panel-type observation (e.g. blood pressure): real values live
                # on each component, not on the parent. Emit one row per component.
                for comp in components:
                    comp_code, comp_description = get_coding(comp, "code")
                    comp_value, comp_unit = get_value(comp)
                    observations.append((
                        str(uuid.uuid5(uuid.NAMESPACE_URL, f"{parent_id}-{comp_code or 'comp'}")),
                        patient_id,
                        encounter_id,
                        comp_code,
                        comp_description,
                        comp_value,
                        comp_unit,
                        observed_at,
                        category,
                    ))
            else:
                code, description = get_coding(resource, "code")
                value, unit = get_value(resource)
                observations.append((
                    parent_id,
                    patient_id,
                    encounter_id,
                    code,
                    description,
                    value,
                    unit,
                    observed_at,
                    category,
                ))
 
        elif rtype == "Procedure":
            code, description = get_coding(resource, "code")
            period = resource.get("performedPeriod", {})
            reason = (resource.get("reasonCode") or [{}])[0]
            reason_coding = (reason.get("coding") or [{}])
            procedures.append((
                resource.get("id"),
                ref_id(resource.get("subject", {}).get("reference")),
                ref_id(resource.get("encounter", {}).get("reference")),
                code,
                description,
                period.get("start"),
                period.get("end"),
                reason_coding[0].get("code") if reason_coding else None,
                reason.get("text"),
            ))
 
    return patients, encounters, conditions, observations, procedures
 
 
# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
 
def main():
    s3 = boto3.client("s3")
    conn = psycopg2.connect(
        host=DB_HOST, port=DB_PORT, dbname=DB_NAME, user=DB_USER, password=DB_PASSWORD
    )
    cur = conn.cursor()
 
    all_patients, all_encounters, all_conditions, all_observations, all_procedures = [], [], [], [], []
 
    paginator = s3.get_paginator("list_objects_v2")
    file_count = 0
    for page in paginator.paginate(Bucket=S3_BUCKET, Prefix=S3_PREFIX):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            if not key.endswith(".json"):
                continue
            body = s3.get_object(Bucket=S3_BUCKET, Key=key)["Body"].read()
            bundle = json.loads(body)
 
            # Skip non-patient bundles (hospital/practitioner info files)
            if not any(e.get("resource", {}).get("resourceType") == "Patient" for e in bundle.get("entry", [])):
                continue
 
            p, e, c, o, pr = parse_bundle(bundle)
            all_patients += p
            all_encounters += e
            all_conditions += c
            all_observations += o
            all_procedures += pr
            file_count += 1
 
    print(f"Parsed {file_count} patient bundles.")
    print(f"Rows -> patients: {len(all_patients)}, encounters: {len(all_encounters)}, "
          f"conditions: {len(all_conditions)}, observations: {len(all_observations)}, "
          f"procedures: {len(all_procedures)}")
 
    # Insert in FK-safe order: patient -> encounter -> condition/observation/procedure
    execute_values(cur, """
        INSERT INTO patient (patient_id, birth_date, gender, race, ethnicity,
                              first_name, last_name, address, city, state, zip)
        VALUES %s ON CONFLICT (patient_id) DO NOTHING
    """, all_patients)
 
    execute_values(cur, """
        INSERT INTO encounter (encounter_id, patient_id, encounter_type, encounter_class,
                                start_time, end_time, reason_code, reason_description,
                                provider_id, organization_id)
        VALUES %s ON CONFLICT (encounter_id) DO NOTHING
    """, all_encounters)
 
    execute_values(cur, """
        INSERT INTO condition (condition_id, patient_id, encounter_id, code, description,
                                onset_date, abatement_date, clinical_status)
        VALUES %s ON CONFLICT (condition_id) DO NOTHING
    """, all_conditions)
 
    execute_values(cur, """
        INSERT INTO observation (observation_id, patient_id, encounter_id, code, description,
                                  value, unit, observed_at, category)
        VALUES %s ON CONFLICT (observation_id) DO NOTHING
    """, all_observations)
 
    execute_values(cur, """
        INSERT INTO procedure (procedure_id, patient_id, encounter_id, code, description,
                                start_time, end_time, reason_code, reason_description)
        VALUES %s ON CONFLICT (procedure_id) DO NOTHING
    """, all_procedures)
 
    conn.commit()
    cur.close()
    conn.close()
    print("Load complete.")
 
 
if __name__ == "__main__":
    main()