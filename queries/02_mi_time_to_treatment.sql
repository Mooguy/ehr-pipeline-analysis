-- MI time-to-treatment: for patients with a myocardial infarction diagnosis,
-- find the earliest cardiac procedure (angiography, catheterization, bypass,
-- angioplasty, stent) linked to that same encounter, and compute the gap.
--
-- FINDING: Synthea generates the condition's onset_date and the procedure's
-- start_time as the exact same timestamp when both occur in the same
-- encounter (verified: hours_to_treatment = 0.0 for every matching patient).
-- This means the synthetic dataset does not model a realistic delay between
-- diagnosis and treatment, so this query cannot support a genuine
-- time-to-treatment metric as-is. Kept here to demonstrate the CTE/join
-- pattern and to document this generator limitation for future reference
-- (e.g. before reusing this logic against real-world data in Phase 7).

WITH mi_diagnosis AS (
    SELECT patient_id, encounter_id, MIN(onset_date) AS mi_diagnosis_time
    FROM condition
    WHERE description ~* 'myocardial infarction'
    GROUP BY patient_id, encounter_id
),
treatment AS (
    SELECT c.patient_id, MIN(pr.start_time) AS treatment_time
    FROM mi_diagnosis c
    JOIN procedure pr ON c.encounter_id = pr.encounter_id
    WHERE pr.description ~* 'bypass|angioplasty|catheterization|stent|cardiac|coronary artery'
    GROUP BY c.patient_id
)
SELECT
    d.patient_id,
    MIN(d.mi_diagnosis_time) AS mi_diagnosis_time,
    t.treatment_time,
    EXTRACT(EPOCH FROM (t.treatment_time - MIN(d.mi_diagnosis_time))) / 3600 AS hours_to_treatment
FROM mi_diagnosis d
JOIN treatment t ON d.patient_id = t.patient_id
GROUP BY d.patient_id, t.treatment_time;
