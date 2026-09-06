-- =====================================================================
-- ops.triage_queue_view
-- Dialect: PostgreSQL 15
-- Encapsulates the corrected Part 1 queue and provenance logic
-- =====================================================================

CREATE OR REPLACE VIEW triage_queue_view AS
WITH canonical_note AS (
    SELECT *
    FROM (
        SELECT
            n.*,
            ROW_NUMBER() OVER (
                PARTITION BY n.note_id
                ORDER BY n.ingested_at_utc DESC, n.ingestion_id DESC
            ) AS rn
        FROM note n
    ) x
    WHERE x.rn = 1
),
rubric AS (
    SELECT
        rubric_version,
        MAX(pass_threshold) AS pass_threshold,
        MAX(weight) FILTER (WHERE dimension = 'accuracy')     AS accuracy_weight,
        MAX(weight) FILTER (WHERE dimension = 'completeness') AS completeness_weight,
        MAX(weight) FILTER (WHERE dimension = 'formatting')   AS formatting_weight,
        MAX(weight) FILTER (WHERE dimension = 'terminology')  AS terminology_weight,
        MAX(weight) FILTER (WHERE dimension = 'hpi')          AS hpi_weight,
        MAX(weight) FILTER (WHERE dimension = 'ros')          AS ros_weight,
        MAX(weight) FILTER (WHERE dimension = 'plan')         AS plan_weight
    FROM rubric_weight
    GROUP BY rubric_version
),
audit_calc AS (
    SELECT
        a.audit_id,
        a.note_id,
        a.auditor_mds_id,
        a.audited_at_utc,
        a.rubric_version,
        a.score_accuracy,
        a.score_completeness,
        a.score_formatting,
        a.score_terminology,
        a.score_hpi,
        a.score_ros,
        a.score_plan,
        a.composite_score AS stored_composite_score,
        a.pass_fail       AS stored_pass_fail,
        r.pass_threshold,
        ROUND((
            r.accuracy_weight     * a.score_accuracy
          + r.completeness_weight * a.score_completeness
          + r.formatting_weight   * a.score_formatting
          + r.terminology_weight  * a.score_terminology
          + r.hpi_weight          * a.score_hpi
          + r.ros_weight          * a.score_ros
          + r.plan_weight         * a.score_plan
        )::numeric, 4) AS composite_score
    FROM note_audit a
    JOIN rubric r
      ON a.rubric_version = r.rubric_version
),
clinician_current AS (
    SELECT *
    FROM (
        SELECT
            c.*,
            ROW_NUMBER() OVER (
                PARTITION BY c.clinician_id
                ORDER BY c.is_current_record DESC, c.record_effective_to DESC NULLS FIRST
            ) AS rn
        FROM clinician c
    ) c_dedup
    WHERE c_dedup.rn = 1
)
SELECT
    n.note_id,
    n.encounter_id,
    n.product_line,
    n.priority,
    n.template_id,
    n.source_channel,
    n.word_count,
    
    m.mds_id,
    m.mds_name,
    m.pod AS mds_pod,
    
    c.clinician_id,
    c.clinician_name,
    c.specialty AS clinician_specialty,
    c.region AS clinician_region,
    
    CASE
        WHEN a.composite_score < a.pass_threshold THEN 'CONFIRMED_AUDIT_FAIL'
        ELSE 'PASS'
    END AS triage_rule,
    
    a.audit_id,
    a.auditor_mds_id,
    a.audited_at_utc,
    a.rubric_version,
    a.composite_score,
    a.pass_threshold,
    ROUND((a.composite_score - a.pass_threshold)::numeric, 4) AS score_gap,
    
    -- Raw 7 dimensions for provenance & QA review
    a.score_accuracy,
    a.score_completeness,
    a.score_formatting,
    a.score_terminology,
    a.score_hpi,
    a.score_ros,
    a.score_plan,
    
    n.submitted_at_utc,
    n.delivered_at_utc,
    (n.submitted_at_utc - INTERVAL '5 hours')::date AS chicago_business_date,
    
    ROUND((EXTRACT(EPOCH FROM (n.delivered_at_utc - n.submitted_at_utc)) / 60.0)::numeric, 1) AS delivery_minutes,
    s.target_minutes,
    s.config_id AS sla_config_id,
    
    CASE
        WHEN n.delivered_at_utc IS NOT NULL
         AND EXTRACT(EPOCH FROM (n.delivered_at_utc - n.submitted_at_utc)) / 60.0 > s.target_minutes
        THEN 'BREACHED'
        ELSE 'OK'
    END AS sla_status,
    
    -- Human-readable provenance description (R5)
    CONCAT(
        'Rule: Composite score (', a.composite_score, ') failed threshold (', a.pass_threshold, 
        ') under rubric ', a.rubric_version, '. Effective SLA target on ', 
        (n.submitted_at_utc - INTERVAL '5 hours')::date, ' was ', s.target_minutes, ' min.'
    ) AS provenance_rule_fired

FROM canonical_note n
JOIN audit_calc a
  ON a.note_id = n.note_id
LEFT JOIN mds m
  ON m.mds_id = n.mds_id
LEFT JOIN clinician_current c
  ON c.clinician_id = n.clinician_id
LEFT JOIN sla_config s
  ON s.product_line = n.product_line
 AND s.priority     = n.priority
 AND (n.submitted_at_utc - INTERVAL '5 hours')::date >= s.effective_from
 AND (s.effective_to IS NULL OR (n.submitted_at_utc - INTERVAL '5 hours')::date <= s.effective_to)
WHERE n.is_void = false
  AND a.composite_score < a.pass_threshold;
