-- 30-day readmission check for cardiac patients: flags cases where a patient
-- had a real admission (emergency or inpatient encounter_class) within 30
-- days of a previous admission. Restricted to EMER/IMP encounter_class only
-- (excludes AMB/VR/HH routine visits, which are expected to recur frequently
-- and initially produced false "readmissions" in the hundreds per patient).

WITH cardiac_admissions AS (
    SELECT 
        patient_id, 
        start_time,
        encounter_class,
        LAG(start_time) OVER (PARTITION BY patient_id ORDER BY start_time) AS previous_admission,
        start_time::date - LAG(start_time) OVER (PARTITION BY patient_id ORDER BY start_time)::date AS days_since_last
    FROM encounter
    WHERE encounter_class IN ('EMER', 'IMP')
      AND patient_id IN (
          SELECT patient_id FROM condition
          WHERE description ~* 'heart|cardiac|coronary|myocardial|hypertension|stroke'
      )
)
SELECT * FROM cardiac_admissions
WHERE days_since_last <= 30;
