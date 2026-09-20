-- Comorbidity clustering: for each non-cardiac condition, compares its rate
-- within the cardiac cohort (patients with a cardiac-relevant condition)
-- against its rate in the overall patient population. A rate_ratio > 1
-- means the condition is over-represented in cardiac patients.
-- Filtered to conditions with >= 10 cardiac patients to avoid noisy ratios
-- from rare conditions with tiny sample sizes.
--
-- FINDING: chronic kidney disease (all stages), diabetes-related kidney
-- complications, metabolic syndrome, and Alzheimer's are all ~2.6-2.9x
-- over-represented in the cardiac cohort — consistent with known real-world
-- cardiac comorbidity patterns (metabolic syndrome / CKD-cardiac link),
-- suggesting Synthea embeds realistic condition co-occurrence relationships.

WITH cardiac_patients AS (
    SELECT DISTINCT patient_id
    FROM condition
    WHERE description ~* 'heart|cardiac|coronary|myocardial|hypertension|stroke'
),

total_patients AS (
    SELECT COUNT(*) AS total
    FROM patient
),

condition_in_cardiac AS (
    SELECT
        c.description,
        COUNT(DISTINCT c.patient_id) AS cardiac_count
    FROM condition c
    JOIN cardiac_patients cp ON c.patient_id = cp.patient_id
    WHERE c.description !~* 'heart|cardiac|coronary|myocardial|hypertension|stroke'
    GROUP BY c.description
),

condition_overall AS (
    SELECT
        description,
        COUNT(DISTINCT patient_id) AS overall_count
    FROM condition
    WHERE description !~* 'heart|cardiac|coronary|myocardial|hypertension|stroke'
    GROUP BY description
)

SELECT
    cic.description,
    cic.cardiac_count AS cardiac_patient_count,
    ROUND((cic.cardiac_count::numeric / (SELECT COUNT(patient_id) FROM cardiac_patients)) * 100, 2) AS cardiac_rate,
    ROUND((co.overall_count::numeric / (SELECT total FROM total_patients)) * 100, 2) AS overall_rate,
    ROUND(
        ((cic.cardiac_count::numeric / (SELECT COUNT(patient_id) FROM cardiac_patients)) * 100) /
        ((co.overall_count::numeric / (SELECT total FROM total_patients)) * 100), 2
    ) AS rate_ratio
FROM condition_in_cardiac cic
JOIN condition_overall co ON cic.description = co.description
WHERE cic.cardiac_count >= 10
ORDER BY rate_ratio DESC;
