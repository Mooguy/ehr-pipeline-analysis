-- Cardiac cohort: patients with at least one cardiac-relevant condition
-- (hypertension, ischemic heart disease, MI, CHF, CABG history, stroke),
-- with basic demographics and the list of matching conditions per patient.

SELECT
    p.patient_id,
    EXTRACT(YEAR FROM AGE(CURRENT_DATE, p.birth_date)) AS age,
    p.gender,
    p.race,
    STRING_AGG(DISTINCT c.description, ', ') AS cardiac_conditions
FROM patient p
JOIN condition c ON p.patient_id = c.patient_id
WHERE c.description ~* 'heart|cardiac|coronary|myocardial|hypertension|stroke'
GROUP BY p.patient_id;
