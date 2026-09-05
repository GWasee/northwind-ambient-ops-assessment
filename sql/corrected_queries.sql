-- =====================================================================
--  Northwind Ambient Ops — Corrected Reporting Queries
--  Dialect: PostgreSQL 15. All *_utc columns are TIMESTAMP (no tz), UTC.
--  Every query can be copied and pasted directly into the Retool Query Library.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Q1  Audit pass rate
--
-- Changes made vs PROVIDED_QUERIES.sql:
--   1. CDT Business Day Window: Replaced BETWEEN midnight UTC with
--      >= '2026-04-01 05:00:00' AND < '2026-07-01 05:00:00' (America/Chicago CDT).
--   2. Excluded Void Notes: Added AND NOT n.is_void.
--   3. Avoided Clinician SCD2 Fan-Out: Removed unneeded JOIN clinician
--      (which matched multiple historical records and multiplied rows for 4 clinicians).
--   4. Recomputed Scores: Recalculated composite_score from raw sub-scores and
--      rubric_weight, bypassing stale ETL precomputations (234 pass/fail mismatches).
--   5. Retool / Postgres Type Cast: Added explicit ::numeric cast inside ROUND()
--      to prevent "function round(real, integer) does not exist".
-- ---------------------------------------------------------------------
WITH recomputed_audit AS (
    SELECT
        a.note_id,
        (SELECT rw.pass_threshold FROM rubric_weight rw WHERE rw.rubric_version = a.rubric_version LIMIT 1) AS pass_threshold,
        ROUND((
            (SELECT rw.weight FROM rubric_weight rw WHERE rw.rubric_version = a.rubric_version AND rw.dimension = 'accuracy')    * a.score_accuracy
          + (SELECT rw.weight FROM rubric_weight rw WHERE rw.rubric_version = a.rubric_version AND rw.dimension = 'completeness') * a.score_completeness
          + (SELECT rw.weight FROM rubric_weight rw WHERE rw.rubric_version = a.rubric_version AND rw.dimension = 'formatting')   * a.score_formatting
          + (SELECT rw.weight FROM rubric_weight rw WHERE rw.rubric_version = a.rubric_version AND rw.dimension = 'terminology')  * a.score_terminology
          + (SELECT rw.weight FROM rubric_weight rw WHERE rw.rubric_version = a.rubric_version AND rw.dimension = 'hpi')         * a.score_hpi
          + (SELECT rw.weight FROM rubric_weight rw WHERE rw.rubric_version = a.rubric_version AND rw.dimension = 'ros')         * a.score_ros
          + (SELECT rw.weight FROM rubric_weight rw WHERE rw.rubric_version = a.rubric_version AND rw.dimension = 'plan')        * a.score_plan
        )::numeric, 4) AS recomp_composite
    FROM note_audit a
)
SELECT
    COUNT(*)                                                          AS audited_notes,
    ROUND((100.0 * SUM(CASE WHEN ra.recomp_composite >= ra.pass_threshold THEN 1 ELSE 0 END)
          / COUNT(*))::numeric, 1)                                    AS pass_rate_pct,
    ROUND(AVG(ra.recomp_composite)::numeric, 4)                       AS avg_composite
FROM note n
JOIN recomputed_audit ra ON ra.note_id = n.note_id
WHERE n.submitted_at_utc >= TIMESTAMP '2026-04-01 05:00:00'
  AND n.submitted_at_utc <  TIMESTAMP '2026-07-01 05:00:00'
  AND NOT n.is_void;


-- ---------------------------------------------------------------------
-- Q2  Delivery SLA breach rate
--
-- Changes made vs PROVIDED_QUERIES.sql:
--   1. CDT Business Day Window: Replaced BETWEEN midnight UTC with
--      >= '2026-04-01 05:00:00' AND < '2026-07-01 05:00:00' (America/Chicago CDT).
--   2. Excluded Void & Undelivered: Added AND NOT n.is_void AND n.delivered_at_utc IS NOT NULL.
--   3. Effective-Dated SLA Join: Added join condition on s.effective_from and s.effective_to
--      to eliminate Cartesian row duplication (pre/post May 15 SLA config rows).
--   4. Removed Defective Escalation Filter: Removed LEFT JOIN escalation / WHERE e.status <> 'RESOLVED'
--      which inadvertently acted as an INNER JOIN, excluding 5,038 unescalated notes.
--   5. Retool / Postgres Type Cast: Added explicit ::numeric cast inside ROUND()
--      to prevent "function round(real, integer) does not exist".
-- ---------------------------------------------------------------------
SELECT
    COUNT(*)                                                          AS notes_measured,
    ROUND((100.0 * SUM(CASE WHEN EXTRACT(EPOCH FROM (n.delivered_at_utc - n.submitted_at_utc))/60.0
                                > s.target_minutes THEN 1 ELSE 0 END)
          / COUNT(*))::numeric, 1)                                    AS breach_rate_pct,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY EXTRACT(EPOCH FROM (n.delivered_at_utc - n.submitted_at_utc))/60.0
    )::numeric, 1)                                                    AS median_minutes
FROM note n
JOIN sla_config s
      ON s.product_line = n.product_line
     AND s.priority     = n.priority
     AND n.submitted_at_utc::date >= s.effective_from
     AND (s.effective_to IS NULL OR n.submitted_at_utc::date <= s.effective_to)
WHERE n.submitted_at_utc >= TIMESTAMP '2026-04-01 05:00:00'
  AND n.submitted_at_utc <  TIMESTAMP '2026-07-01 05:00:00'
  AND NOT n.is_void
  AND n.delivered_at_utc IS NOT NULL;


-- ---------------------------------------------------------------------
-- Q3  Daily volume + anomaly flag
--
-- Changes made vs PROVIDED_QUERIES.sql:
--   1. Chicago Calendar Day: Converted UTC timestamp to Chicago local date
--      ((n.submitted_at_utc - INTERVAL '5 hours')::date) to align with business day.
--   2. Excluded Void Notes: Added AND NOT n.is_void.
--   3. Weekday Filter: Applied the 30% drop anomaly flag only to weekdays
--      (EXTRACT(DOW FROM submit_day)::int BETWEEN 1 AND 5) per the business rule,
--      preventing zero-volume weekends from being falsely flagged.
--   4. Retool / Postgres Type Cast: Added explicit ::numeric cast inside ROUND()
--      to prevent "function round(real, integer) does not exist".
-- ---------------------------------------------------------------------
WITH daily AS (
    SELECT
        (n.submitted_at_utc - INTERVAL '5 hours')::date               AS submit_day,
        COUNT(*)                                                      AS notes
    FROM note n
    WHERE (n.submitted_at_utc - INTERVAL '5 hours')::date BETWEEN DATE '2026-04-01' AND DATE '2026-06-30'
      AND NOT n.is_void
    GROUP BY 1
)
SELECT
    submit_day,
    notes,
    ROUND(AVG(notes) OVER (ORDER BY submit_day ROWS BETWEEN 14 PRECEDING AND 1 PRECEDING)::numeric, 1) AS trailing_avg,
    CASE WHEN EXTRACT(DOW FROM submit_day)::int BETWEEN 1 AND 5
          AND notes < 0.70 * AVG(notes) OVER (ORDER BY submit_day ROWS BETWEEN 14 PRECEDING AND 1 PRECEDING)
         THEN 'ANOMALY' END                                           AS flag
FROM daily
ORDER BY submit_day;


-- ---------------------------------------------------------------------
-- Q4  MDS leaderboard
--
-- Changes made vs PROVIDED_QUERIES.sql:
--   1. Stable Grouping Key: Grouped by m.mds_id, m.mds_name, m.status because mds_name
--      is non-unique ("Domingo, Rafael" exists under two distinct IDs: MD-206 and MD-227).
--   2. CDT Business Day Window: Filtered submitted_at_utc >= '2026-04-01 05:00:00'
--      AND < '2026-07-01 05:00:00' (America/Chicago CDT).
--   3. Excluded Void Notes: Added AND NOT n.is_void.
--   4. NULL-Aware Word Count: Used AVG(n.word_count) without COALESCE(..., 0) because
--      NULL represents missing audio transcript, not a zero-word note.
--   5. Recomputed Scores: Recomputed composite_score from raw rubric sub-scores and weights.
--   6. Retool / Postgres Type Cast: Added explicit ::numeric cast inside ROUND()
--      to prevent "function round(real, integer) does not exist".
-- ---------------------------------------------------------------------
WITH recomputed_audit AS (
    SELECT
        a.note_id,
        ROUND((
            (SELECT rw.weight FROM rubric_weight rw WHERE rw.rubric_version = a.rubric_version AND rw.dimension = 'accuracy')    * a.score_accuracy
          + (SELECT rw.weight FROM rubric_weight rw WHERE rw.rubric_version = a.rubric_version AND rw.dimension = 'completeness') * a.score_completeness
          + (SELECT rw.weight FROM rubric_weight rw WHERE rw.rubric_version = a.rubric_version AND rw.dimension = 'formatting')   * a.score_formatting
          + (SELECT rw.weight FROM rubric_weight rw WHERE rw.rubric_version = a.rubric_version AND rw.dimension = 'terminology')  * a.score_terminology
          + (SELECT rw.weight FROM rubric_weight rw WHERE rw.rubric_version = a.rubric_version AND rw.dimension = 'hpi')         * a.score_hpi
          + (SELECT rw.weight FROM rubric_weight rw WHERE rw.rubric_version = a.rubric_version AND rw.dimension = 'ros')         * a.score_ros
          + (SELECT rw.weight FROM rubric_weight rw WHERE rw.rubric_version = a.rubric_version AND rw.dimension = 'plan')        * a.score_plan
        )::numeric, 4) AS recomp_composite
    FROM note_audit a
)
SELECT
    m.mds_id,
    m.mds_name,
    m.status,
    COUNT(*)                                                          AS notes_handled,
    ROUND(AVG(n.word_count)::numeric, 1)                              AS avg_word_count,
    ROUND(AVG(ra.recomp_composite)::numeric, 4)                       AS avg_composite,
    SUM(CASE WHEN n.word_count < 50 THEN 1 ELSE 0 END)                AS short_note_flags
FROM note n
JOIN mds m ON m.mds_id = n.mds_id
LEFT JOIN recomputed_audit ra ON ra.note_id = n.note_id
WHERE n.submitted_at_utc >= TIMESTAMP '2026-04-01 05:00:00'
  AND n.submitted_at_utc <  TIMESTAMP '2026-07-01 05:00:00'
  AND NOT n.is_void
GROUP BY m.mds_id, m.mds_name, m.status
ORDER BY avg_composite DESC NULLS LAST, notes_handled DESC;


-- ---------------------------------------------------------------------
-- Q5  Escalation health
--
-- Changes made vs PROVIDED_QUERIES.sql:
--   1. CDT Business Day Window: Filtered created_at_utc >= '2026-04-01 05:00:00'
--      AND < '2026-07-01 05:00:00' (America/Chicago CDT).
--   2. Isolated Active Escalations: Filtered status = 'OPEN' instead of status <> 'RESOLVED'
--      to exclude 43 PENDING_POST queue items that were never delivered to Slack or assigned.
--   3. Retool / Postgres Type Cast: Maintained explicit ::numeric cast inside ROUND().
-- ---------------------------------------------------------------------
SELECT
    COUNT(*)                                                          AS open_escalations,
    ROUND(AVG(EXTRACT(EPOCH FROM (e.first_response_at_utc - e.created_at_utc))/60.0)::numeric, 1)
                                                                      AS avg_minutes_to_first_response,
    MIN(e.created_at_utc)                                             AS oldest_open
FROM escalation e
WHERE e.status = 'OPEN'
  AND e.created_at_utc >= TIMESTAMP '2026-04-01 05:00:00'
  AND e.created_at_utc <  TIMESTAMP '2026-07-01 05:00:00';
