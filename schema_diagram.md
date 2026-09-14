# EHR Pipeline — Database Schema

```mermaid
erDiagram
    PATIENT ||--o{ ENCOUNTER : has
    PATIENT ||--o{ CONDITION : has
    PATIENT ||--o{ OBSERVATION : has
    PATIENT ||--o{ PROCEDURE : has
    ENCOUNTER ||--o{ CONDITION : "diagnosed during"
    ENCOUNTER ||--o{ OBSERVATION : "recorded during"
    ENCOUNTER ||--o{ PROCEDURE : "performed during"

    PATIENT {
        uuid patient_id PK
        date birth_date
        text gender
        text race
        text ethnicity
        text first_name
        text last_name
        text address
        text city
        text state
        text zip
    }
    ENCOUNTER {
        uuid encounter_id PK
        uuid patient_id FK
        text encounter_type
        text encounter_class
        timestamp start_time
        timestamp end_time
        text reason_code
        text reason_description
        text provider_id
        text organization_id
    }
    CONDITION {
        uuid condition_id PK
        uuid patient_id FK
        uuid encounter_id FK
        text code
        text description
        timestamp onset_date
        timestamp abatement_date
        text clinical_status
    }
    OBSERVATION {
        uuid observation_id PK
        uuid patient_id FK
        uuid encounter_id FK
        text code
        text description
        text value
        text unit
        timestamp observed_at
        text category
    }
    PROCEDURE {
        uuid procedure_id PK
        uuid patient_id FK
        uuid encounter_id FK
        text code
        text description
        timestamp start_time
        timestamp end_time
        text reason_code
        text reason_description
    }
```

## How the tables relate

- **patient** is the anchor — every other table points back to it via `patient_id`.
- **encounter** is a visit. `condition`, `observation`, and `procedure` each optionally link to the specific encounter they happened during, in addition to the patient.
- A patient can have many encounters; each encounter can have many conditions, observations, and procedures tied to it.
