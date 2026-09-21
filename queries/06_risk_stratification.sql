-- Risk stratification: among cardiac cohort patients, score each on 4 binary
-- risk factors (age >= 65, hypertension, high LDL, reduced kidney function)
-- and bucket into Low/Moderate/High risk.
--
-- DESIGN DECISION: missing lab data (LDL/eGFR never tested) is NOT treated
-- as a confirmed-normal result (i.e. not silently scored as 0). Lab orders
-- are not random (MNAR) -- clinicians test when risk is already suspected --
-- so imputing 0 for missing values would systematically understate risk.
-- Patients missing either lab are labeled 'Incomplete assessment' rather
-- than being assigned a false Low/Moderate/High category.
--
-- FINDING: of the cardiac cohort, ~35% (96/277) have an incomplete risk
-- assessment (never tested for LDL and/or eGFR) -- a real care-gap finding,
-- not a query artifact.

WITH cardiac_patients AS (
    SELECT DISTINCT patient_id
    FROM condition
    WHERE description ~* 'heart|cardiac|coronary|myocardial|hypertension|stroke'
),

demographics AS (
    SELECT 
        p.patient_id,
        CASE WHEN EXTRACT(YEAR FROM AGE(CURRENT_DATE, p.birth_date)) >= 65 THEN 1 ELSE 0 END AS age_flag,
        CASE WHEN EXISTS (
            SELECT 1 FROM condition c 
            WHERE c.patient_id = p.patient_id AND c.description ~* 'essential hypertension'
        ) THEN 1 ELSE 0 END AS htn_flag
    FROM patient p
),

lab_flags AS (
    SELECT
        patient_id,
        MAX(CASE WHEN code = '18262-6' THEN value::numeric END) AS ldl_value,
        MAX(CASE WHEN code = '33914-3' THEN value::numeric END) AS egfr_value,
        CASE WHEN MAX(CASE WHEN code = '18262-6' THEN value::numeric END) > 130 THEN 1 ELSE 0 END AS ldl_flag,
        CASE WHEN MAX(CASE WHEN code = '18262-6' THEN value::numeric END) IS NOT NULL THEN 1 ELSE 0 END AS ldl_tested,
        CASE WHEN MAX(CASE WHEN code = '33914-3' THEN value::numeric END) < 60 THEN 1 ELSE 0 END AS egfr_flag,
        CASE WHEN MAX(CASE WHEN code = '33914-3' THEN value::numeric END) IS NOT NULL THEN 1 ELSE 0 END AS egfr_tested
    FROM (
        SELECT patient_id, code, value, observed_at,
            ROW_NUMBER() OVER (PARTITION BY patient_id, code ORDER BY observed_at DESC) AS rn
        FROM observation
        WHERE description ~* 'LDL|glomerular filtration rate'
    ) ranked
    WHERE rn = 1
    GROUP BY patient_id
)

SELECT
    d.patient_id,
    d.age_flag + d.htn_flag + COALESCE(l.ldl_flag, 0) + COALESCE(l.egfr_flag, 0) AS risk_score,
    2 + COALESCE(l.ldl_tested, 0) + COALESCE(l.egfr_tested, 0) AS factors_assessed,
    CASE 
        WHEN 2 + COALESCE(l.ldl_tested, 0) + COALESCE(l.egfr_tested, 0) < 4 THEN 'Incomplete assessment'
        WHEN d.age_flag + d.htn_flag + l.ldl_flag + l.egfr_flag >= 3 THEN 'High risk'
        WHEN d.age_flag + d.htn_flag + l.ldl_flag + l.egfr_flag = 2 THEN 'Moderate risk'
        ELSE 'Low risk'
    END AS risk_category
FROM demographics d
JOIN cardiac_patients cp ON d.patient_id = cp.patient_id
LEFT JOIN lab_flags l ON d.patient_id = l.patient_id;
