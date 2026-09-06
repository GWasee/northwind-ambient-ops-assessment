-- =====================================================================
-- Northwind Ambient Ops — Corrected Reporting Queries
-- Dialect: PostgreSQL 15
-- *_utc columns are TIMESTAMP WITHOUT TIME ZONE containing UTC instants.
-- Each numbered query is standalone and can be pasted into Retool Query Library.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Q1  Audit pass rate
--
-- Corrections vs PROVIDED_QUERIES.sql:
--   1. Resolve note re-ingestions to one logical note using latest ingested_at_utc.
--   2. Use the America/Chicago Q2 business-day UTC boundaries.
--   3. Exclude void notes.
--   4. Remove the unnecessary clinician SCD2 join that can fan out rows.
--   5. Recompute composite score and pass/fail from raw audit dimensions using
--      the weights and threshold for the audit's recorded rubric_version.
-- ---------------------------------------------------------------------
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
        MAX(weight) FILTER (WHERE dimension = 'accuracy')     AS w_accuracy,
        MAX(weight) FILTER (WHERE dimension = 'completeness') AS w_completeness,
        MAX(weight) FILTER (WHERE dimension = 'formatting')   AS w_formatting,
        MAX(weight) FILTER (WHERE dimension = 'terminology')  AS w_terminology,
        MAX(weight) FILTER (WHERE dimension = 'hpi')          AS w_hpi,
        MAX(weight) FILTER (WHERE dimension = 'ros')          AS w_ros,
        MAX(weight) FILTER (WHERE dimension = 'plan')         AS w_plan
    FROM rubric_weight
    GROUP BY rubric_version
),
recomputed_audit AS (
    SELECT
        a.note_id,
        r.pass_threshold,
        (
            r.w_accuracy     * a.score_accuracy
          + r.w_completeness * a.score_completeness
          + r.w_formatting   * a.score_formatting
          + r.w_terminology  * a.score_terminology
          + r.w_hpi          * a.score_hpi
          + r.w_ros          * a.score_ros
          + r.w_plan         * a.score_plan
        ) AS recomp_composite
    FROM note_audit a
    JOIN rubric r
      ON r.rubric_version = a.rubric_version
)
SELECT
    COUNT(*) AS audited_notes,
    ROUND(
        (
            100.0 * COUNT(*) FILTER (
                WHERE ra.recomp_composite >= ra.pass_threshold
            ) / NULLIF(COUNT(*), 0)
        )::numeric,
        1
    ) AS pass_rate_pct,
    ROUND(AVG(ra.recomp_composite)::numeric, 4) AS avg_composite
FROM canonical_note n
JOIN recomputed_audit ra
  ON ra.note_id = n.note_id
WHERE n.submitted_at_utc >= TIMESTAMP '2026-04-01 05:00:00'
  AND n.submitted_at_utc <  TIMESTAMP '2026-07-01 05:00:00'
  AND NOT n.is_void;


-- ---------------------------------------------------------------------
-- Q2  Delivery SLA breach rate
--
-- Corrections vs PROVIDED_QUERIES.sql:
--   1. Resolve note re-ingestions to one logical note using latest ingested_at_utc.
--   2. Use the America/Chicago Q2 business-day UTC boundaries.
--   3. Exclude void and undelivered notes.
--   4. Match the effective-dated SLA using the note's America/Chicago
--      business date, not its UTC calendar date.
--   5. Remove the escalation join/filter, which excluded notes with no escalation.
-- ---------------------------------------------------------------------
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
eligible AS (
    SELECT
        n.*,
        (n.submitted_at_utc - INTERVAL '5 hours')::date AS chicago_business_date
    FROM canonical_note n
    WHERE n.submitted_at_utc >= TIMESTAMP '2026-04-01 05:00:00'
      AND n.submitted_at_utc <  TIMESTAMP '2026-07-01 05:00:00'
      AND NOT n.is_void
      AND n.delivered_at_utc IS NOT NULL
)
SELECT
    COUNT(*) AS notes_measured,
    ROUND(
        (
            100.0 * COUNT(*) FILTER (
                WHERE EXTRACT(EPOCH FROM (n.delivered_at_utc - n.submitted_at_utc)) / 60.0
                      > s.target_minutes
            ) / NULLIF(COUNT(*), 0)
        )::numeric,
        1
    ) AS breach_rate_pct,
    ROUND(
        PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY EXTRACT(EPOCH FROM (n.delivered_at_utc - n.submitted_at_utc)) / 60.0
        )::numeric,
        1
    ) AS median_minutes
FROM eligible n
JOIN sla_config s
  ON s.product_line = n.product_line
 AND s.priority = n.priority
 AND n.chicago_business_date >= s.effective_from
 AND (s.effective_to IS NULL OR n.chicago_business_date <= s.effective_to);


-- ---------------------------------------------------------------------
-- Q3  Daily volume + anomaly flag
--
-- Business rule: flag any weekday more than 30% below the trailing
-- 14-calendar-day average.
--
-- Corrections vs PROVIDED_QUERIES.sql:
--   1. Resolve note re-ingestions to one logical note using latest ingested_at_utc.
--   2. Convert UTC timestamps to the America/Chicago business date.
--   3. Exclude void notes.
--   4. Generate all 91 Q2 calendar dates so zero-volume days are retained.
--   5. Apply the anomaly flag only to weekdays while keeping all calendar days
--      in the 14-day trailing baseline.
-- ---------------------------------------------------------------------
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
calendar AS (
    SELECT gs::date AS submit_day
    FROM generate_series(
        TIMESTAMP '2026-04-01 00:00:00',
        TIMESTAMP '2026-06-30 00:00:00',
        INTERVAL '1 day'
    ) AS gs
),
daily_counts AS (
    SELECT
        (n.submitted_at_utc - INTERVAL '5 hours')::date AS submit_day,
        COUNT(*) AS notes
    FROM canonical_note n
    WHERE n.submitted_at_utc >= TIMESTAMP '2026-04-01 05:00:00'
      AND n.submitted_at_utc <  TIMESTAMP '2026-07-01 05:00:00'
      AND NOT n.is_void
    GROUP BY 1
),
daily AS (
    SELECT
        c.submit_day,
        COALESCE(d.notes, 0) AS notes
    FROM calendar c
    LEFT JOIN daily_counts d
      ON d.submit_day = c.submit_day
),
scored AS (
    SELECT
        submit_day,
        notes,
        AVG(notes) OVER (
            ORDER BY submit_day
            ROWS BETWEEN 14 PRECEDING AND 1 PRECEDING
        ) AS trailing_avg
    FROM daily
)
SELECT
    submit_day,
    notes,
    ROUND(trailing_avg::numeric, 1) AS trailing_avg,
    CASE
        WHEN EXTRACT(DOW FROM submit_day)::int BETWEEN 1 AND 5
         AND trailing_avg IS NOT NULL
         AND notes < 0.70 * trailing_avg
        THEN 'ANOMALY'
    END AS flag
FROM scored
ORDER BY submit_day;


-- ---------------------------------------------------------------------
-- Q4  MDS leaderboard
--
-- Corrections vs PROVIDED_QUERIES.sql:
--   1. Resolve note re-ingestions to one logical note using latest ingested_at_utc.
--   2. Group by stable mds_id as well as display name because mds_name is not unique.
--   3. Use the America/Chicago Q2 business-day UTC boundaries.
--   4. Exclude void notes.
--   5. Preserve NULL word_count instead of converting missing transcripts to zero.
--   6. Recompute audit composite scores from the raw dimensions and rubric weights.
--   7. Rank by the unrounded average composite; round only the displayed value.
-- ---------------------------------------------------------------------
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
        MAX(weight) FILTER (WHERE dimension = 'accuracy')     AS w_accuracy,
        MAX(weight) FILTER (WHERE dimension = 'completeness') AS w_completeness,
        MAX(weight) FILTER (WHERE dimension = 'formatting')   AS w_formatting,
        MAX(weight) FILTER (WHERE dimension = 'terminology')  AS w_terminology,
        MAX(weight) FILTER (WHERE dimension = 'hpi')          AS w_hpi,
        MAX(weight) FILTER (WHERE dimension = 'ros')          AS w_ros,
        MAX(weight) FILTER (WHERE dimension = 'plan')         AS w_plan
    FROM rubric_weight
    GROUP BY rubric_version
),
recomputed_audit AS (
    SELECT
        a.note_id,
        (
            r.w_accuracy     * a.score_accuracy
          + r.w_completeness * a.score_completeness
          + r.w_formatting   * a.score_formatting
          + r.w_terminology  * a.score_terminology
          + r.w_hpi          * a.score_hpi
          + r.w_ros          * a.score_ros
          + r.w_plan         * a.score_plan
        ) AS recomp_composite
    FROM note_audit a
    JOIN rubric r
      ON r.rubric_version = a.rubric_version
),
leaderboard AS (
    SELECT
        m.mds_id,
        m.mds_name,
        m.status,
        COUNT(*) AS notes_handled,
        AVG(n.word_count) AS avg_word_count_raw,
        AVG(ra.recomp_composite) AS avg_composite_raw,
        SUM(CASE WHEN n.word_count < 50 THEN 1 ELSE 0 END) AS short_note_flags
    FROM canonical_note n
    JOIN mds m
      ON m.mds_id = n.mds_id
    LEFT JOIN recomputed_audit ra
      ON ra.note_id = n.note_id
    WHERE n.submitted_at_utc >= TIMESTAMP '2026-04-01 05:00:00'
      AND n.submitted_at_utc <  TIMESTAMP '2026-07-01 05:00:00'
      AND NOT n.is_void
    GROUP BY m.mds_id, m.mds_name, m.status
)
SELECT
    mds_id,
    mds_name,
    status,
    notes_handled,
    ROUND(avg_word_count_raw::numeric, 1) AS avg_word_count,
    ROUND(avg_composite_raw::numeric, 4) AS avg_composite,
    short_note_flags
FROM leaderboard
ORDER BY avg_composite_raw DESC NULLS LAST,
         notes_handled DESC,
         mds_id;


-- ---------------------------------------------------------------------
-- Q5  Escalation health
--
-- Corrections vs PROVIDED_QUERIES.sql:
--   1. Use the America/Chicago Q2 business-day UTC boundaries.
--   2. Count status = 'OPEN' only. PENDING_POST is a posting/workflow state:
--      the database row exists but the Slack post has not completed.
-- ---------------------------------------------------------------------
SELECT
    COUNT(*) AS open_escalations,
    ROUND(
        AVG(
            EXTRACT(EPOCH FROM (e.first_response_at_utc - e.created_at_utc)) / 60.0
        )::numeric,
        1
    ) AS avg_minutes_to_first_response,
    MIN(e.created_at_utc) AS oldest_open
FROM escalation e
WHERE e.status = 'OPEN'
  AND e.created_at_utc >= TIMESTAMP '2026-04-01 05:00:00'
  AND e.created_at_utc <  TIMESTAMP '2026-07-01 05:00:00';