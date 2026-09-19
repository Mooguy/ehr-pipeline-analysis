-- Lab abnormality flags: for each patient, their most recent LDL cholesterol
-- and eGFR (kidney function) readings, flagged as abnormal against standard
-- clinical thresholds (LDL > 130 mg/dL, eGFR < 60). Patients missing a
-- reading entirely are flagged "No data" rather than defaulting to "Normal".

WITH cte AS (
    SELECT
        patient_id,
        observed_at,
        code,
        value,
        ROW_NUMBER() OVER (PARTITION BY patient_id, code ORDER BY observed_at DESC) AS rn
    FROM observation
    WHERE description ~* 'LDL|glomerular filtration rate'
)

SELECT 
    patient_id,
    MAX(CASE WHEN code = '18262-6' THEN value::numeric END) AS ldl_value,
    MAX(CASE WHEN code = '33914-3' THEN value::numeric END) AS egfr_value,
    CASE 
        WHEN MAX(CASE WHEN code = '18262-6' THEN value::numeric END) IS NULL THEN 'No data'
        WHEN MAX(CASE WHEN code = '18262-6' THEN value::numeric END) > 130 THEN 'High LDL' 
        ELSE 'Normal' 
    END AS ldl_flag,
    CASE 
        WHEN MAX(CASE WHEN code = '33914-3' THEN value::numeric END) IS NULL THEN 'No data'
        WHEN MAX(CASE WHEN code = '33914-3' THEN value::numeric END) < 60 THEN 'Reduced kidney function' 
        ELSE 'Normal' 
    END AS egfr_flag
FROM cte
WHERE rn = 1
GROUP BY patient_id;
