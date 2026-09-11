-- Aidoc EHR Pipeline: Relational schema for flattened FHIR resources

CREATE TABLE patient (
    patient_id UUID PRIMARY KEY,
    birth_date DATE,
    gender TEXT,
    race TEXT,
    ethnicity TEXT,
    first_name TEXT,
    last_name TEXT,
    address TEXT,
    city TEXT,
    state TEXT,
    zip TEXT
);

CREATE TABLE encounter (
    encounter_id UUID PRIMARY KEY,
    patient_id UUID REFERENCES patient(patient_id),
    encounter_type TEXT,
    encounter_class TEXT,
    start_time TIMESTAMP,
    end_time TIMESTAMP,
    reason_code TEXT,
    reason_description TEXT,
    provider_id TEXT,
    organization_id TEXT
);

CREATE TABLE condition (
    condition_id UUID PRIMARY KEY,
    patient_id UUID REFERENCES patient(patient_id),
    encounter_id UUID REFERENCES encounter(encounter_id),
    code TEXT,
    description TEXT,
    onset_date TIMESTAMP,
    abatement_date TIMESTAMP,
    clinical_status TEXT
);

CREATE TABLE observation (
    observation_id UUID PRIMARY KEY,
    patient_id UUID REFERENCES patient(patient_id),
    encounter_id UUID REFERENCES encounter(encounter_id),
    code TEXT,
    description TEXT,
    value TEXT,
    unit TEXT,
    observed_at TIMESTAMP,
    category TEXT
);

CREATE TABLE procedure (
    procedure_id UUID PRIMARY KEY,
    patient_id UUID REFERENCES patient(patient_id),
    encounter_id UUID REFERENCES encounter(encounter_id),
    code TEXT,
    description TEXT,
    start_time TIMESTAMP,
    end_time TIMESTAMP,
    reason_code TEXT,
    reason_description TEXT
);
