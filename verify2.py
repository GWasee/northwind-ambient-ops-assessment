"""
Final verification: confirm every figure in RECONCILIATION.md matches query output.

IMPORTANT: every block below mirrors sql/corrected_queries.sql line-for-line in its
logic (same canonical_note CTE, same Chicago-business-date window, same rubric
recompute). This script is a drift-check between the markdown and the SQL that
actually ships in the repo -- it must NOT reintroduce the un-deduped note grain
that produced the rejected 1,583/5,510 draft figures documented in AI_USAGE.md
as an override case.
"""
import duckdb, sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

con = duckdb.connect()
DATA = 'data'
con.execute(f"CREATE TABLE note AS SELECT * FROM read_csv_auto('{DATA}/note.csv', header=True)")
con.execute(f"CREATE TABLE note_audit AS SELECT * FROM read_csv_auto('{DATA}/note_audit.csv', header=True)")
con.execute(f"CREATE TABLE clinician AS SELECT * FROM read_csv_auto('{DATA}/clinician.csv', header=True)")
con.execute(f"CREATE TABLE mds AS SELECT * FROM read_csv_auto('{DATA}/mds.csv', header=True)")
con.execute(f"CREATE TABLE rubric_weight AS SELECT * FROM read_csv_auto('{DATA}/rubric_weight.csv', header=True)")
con.execute(f"CREATE TABLE sla_config AS SELECT * FROM read_csv_auto('{DATA}/sla_config.csv', header=True)")
con.execute(f"CREATE TABLE escalation AS SELECT * FROM read_csv_auto('{DATA}/escalation.csv', header=True)")

# Shared canonical_note CTE text, reused verbatim in every query below so there is
# exactly one place to change the dedup rule if it ever needs to.
CANONICAL_NOTE = """
canonical_note AS (
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
)
"""

def check(label, sql, expected, tol=0.05):
    row = con.execute(sql).fetchone()
    result = tuple(row)
    ok = all(
        abs(float(r) - float(e)) < tol if isinstance(e, float) else str(r) == str(e)
        for r, e in zip(result, expected)
    )
    status = "PASS" if ok else "FAIL - MISMATCH"
    print(f"  [{status}]  {label}")
    if not ok:
        print(f"       expected: {expected}")
        print(f"       got:      {result}")
    return ok

all_ok = True
print("=== Verification of figures in RECONCILIATION.md ===")
print("=== (mirrors sql/corrected_queries.sql; canonical_note dedup applied everywhere) ===")
print()

# ---------------------------------------------------------------------
# CQ1 -- audited notes / pass rate / avg composite
# Matches sql/corrected_queries.sql Q1: canonical_note dedup, Chicago Q2
# window, void exclusion, no clinician join, recomputed composite/threshold
# from raw scores + the audit's recorded rubric_version.
# RECONCILIATION.md 3.2 / 3.3 final row: 1,566 audited notes, 76.8% pass
# rate, 0.9161 avg composite.
# ---------------------------------------------------------------------
print("--- CQ1 True values ---")
all_ok &= check("Audited notes: 1,566 | pass rate: 76.8% | avg composite: 0.9161", f"""
WITH {CANONICAL_NOTE},
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
        ROUND(
            r.w_accuracy     * a.score_accuracy
          + r.w_completeness * a.score_completeness
          + r.w_formatting   * a.score_formatting
          + r.w_terminology  * a.score_terminology
          + r.w_hpi          * a.score_hpi
          + r.w_ros          * a.score_ros
          + r.w_plan         * a.score_plan
        , 4) AS recomp_composite
    FROM note_audit a
    JOIN rubric r ON r.rubric_version = a.rubric_version
)
SELECT
    COUNT(*),
    ROUND(100.0 * COUNT(*) FILTER (WHERE ra.recomp_composite >= ra.pass_threshold) / COUNT(*), 1),
    ROUND(AVG(ra.recomp_composite), 4)
FROM canonical_note n
JOIN recomputed_audit ra ON ra.note_id = n.note_id
WHERE n.submitted_at_utc >= TIMESTAMP '2026-04-01 05:00:00'
  AND n.submitted_at_utc <  TIMESTAMP '2026-07-01 05:00:00'
  AND NOT n.is_void
""", (1566, 76.8, 0.9161))

# ---------------------------------------------------------------------
# CQ2 -- SLA breach rate / median delivery / population measured
# Matches sql/corrected_queries.sql Q2: canonical_note dedup, Chicago Q2
# window, void + undelivered exclusion, effective-dated SLA match on the
# note's Chicago business date, no escalation-join restriction.
# RECONCILIATION.md 3.2 / 3.3 final row: 5,449 notes measured, 10.4%
# breach rate, 18.1 min median.
# ---------------------------------------------------------------------
print()
print("--- CQ2 True values ---")
all_ok &= check("Notes measured: 5,449 | breach rate: 10.4% | median: 18.1 min", f"""
WITH {CANONICAL_NOTE},
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
    COUNT(*),
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE EXTRACT(EPOCH FROM (n.delivered_at_utc - n.submitted_at_utc)) / 60.0 > s.target_minutes
        ) / COUNT(*)
    , 1),
    ROUND(median(EXTRACT(EPOCH FROM (n.delivered_at_utc - n.submitted_at_utc)) / 60.0), 1)
FROM eligible n
JOIN sla_config s
  ON s.product_line = n.product_line
 AND s.priority = n.priority
 AND n.chicago_business_date >= s.effective_from
 AND (s.effective_to IS NULL OR n.chicago_business_date <= s.effective_to)
""", (5449, 10.4, 18.1))

# ---------------------------------------------------------------------
# CQ3 -- daily volume anomaly flag
# Matches sql/corrected_queries.sql Q3: canonical_note dedup, Chicago
# business date, full 91-day calendar generated so zero-volume days
# survive, flag applied to weekdays only.
# RECONCILIATION.md 3.3 final row: 2 anomaly weekdays out of 65.
# ---------------------------------------------------------------------
print()
print("--- CQ3 True values ---")
all_ok &= check("Anomaly weekdays: 2 (of 65)", f"""
WITH {CANONICAL_NOTE},
calendar AS (
    SELECT gs::date AS submit_day
    FROM generate_series(
        TIMESTAMP '2026-04-01 00:00:00',
        TIMESTAMP '2026-06-30 00:00:00',
        INTERVAL '1 day'
    ) AS t(gs)
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
    SELECT c.submit_day, COALESCE(d.notes, 0) AS notes
    FROM calendar c
    LEFT JOIN daily_counts d ON d.submit_day = c.submit_day
),
scored AS (
    SELECT
        submit_day,
        notes,
        AVG(notes) OVER (ORDER BY submit_day ROWS BETWEEN 14 PRECEDING AND 1 PRECEDING) AS trailing_avg
    FROM daily
)
SELECT
    SUM(CASE
        WHEN EXTRACT(DOW FROM submit_day)::int BETWEEN 1 AND 5
         AND trailing_avg IS NOT NULL
         AND notes < 0.70 * trailing_avg
        THEN 1 ELSE 0
    END)
FROM scored
""", (2,))

# ---------------------------------------------------------------------
# CQ4 -- MDS leaderboard, top by unrounded avg composite
# Matches sql/corrected_queries.sql Q4: canonical_note dedup, grouped by
# mds_id (not mds_name), Chicago Q2 window, void exclusion, recomputed
# composite, ranked by unrounded average.
# This figure is not independently stated in RECONCILIATION.md's prose,
# so treat it as a sanity check on the leaderboard logic rather than a
# markdown cross-reference.
# ---------------------------------------------------------------------
print()
print("--- CQ4 leaderboard sanity check (not asserted in RECONCILIATION.md prose) ---")
r = con.execute(f"""
WITH {CANONICAL_NOTE},
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
    JOIN rubric r ON r.rubric_version = a.rubric_version
),
leaderboard AS (
    SELECT
        m.mds_id,
        m.mds_name,
        m.status,
        COUNT(*) AS notes_handled,
        AVG(ra.recomp_composite) AS avg_composite_raw
    FROM canonical_note n
    JOIN mds m ON m.mds_id = n.mds_id
    LEFT JOIN recomputed_audit ra ON ra.note_id = n.note_id
    WHERE n.submitted_at_utc >= TIMESTAMP '2026-04-01 05:00:00'
      AND n.submitted_at_utc <  TIMESTAMP '2026-07-01 05:00:00'
      AND NOT n.is_void
    GROUP BY m.mds_id, m.mds_name, m.status
)
SELECT mds_id, mds_name, status, notes_handled, ROUND(avg_composite_raw, 4)
FROM leaderboard
ORDER BY avg_composite_raw DESC NULLS LAST, notes_handled DESC, mds_id
LIMIT 1
""").fetchone()
print(f"  Top MDS: {r[0]} {r[1]} (status={r[2]}) | notes: {r[3]} | avg_composite: {r[4]}")

# Cross-check the specific name-collision claim in RECONCILIATION.md 3.4:
# MD-206 and MD-227 both display as "Domingo, Rafael"; MD-206 sits in the
# genuine bottom five (~0.903) while MD-227 ranks around #7 (~0.926).
print()
print("--- Name-collision check: MD-206 vs MD-227 (RECONCILIATION.md 3.4) ---")
rows = con.execute(f"""
WITH {CANONICAL_NOTE},
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
    JOIN rubric r ON r.rubric_version = a.rubric_version
)
SELECT
    m.mds_id, m.mds_name, m.status,
    COUNT(*) AS notes_handled,
    ROUND(AVG(ra.recomp_composite), 4) AS avg_composite
FROM canonical_note n
JOIN mds m ON m.mds_id = n.mds_id
LEFT JOIN recomputed_audit ra ON ra.note_id = n.note_id
WHERE n.submitted_at_utc >= TIMESTAMP '2026-04-01 05:00:00'
  AND n.submitted_at_utc <  TIMESTAMP '2026-07-01 05:00:00'
  AND NOT n.is_void
  AND m.mds_id IN ('MD-206', 'MD-227')
GROUP BY m.mds_id, m.mds_name, m.status
ORDER BY m.mds_id
""").fetchall()
for row in rows:
    print(f"  {row[0]} {row[1]} (status={row[2]}) | notes: {row[3]} | avg_composite: {row[4]}")

# ---------------------------------------------------------------------
# CQ5 -- open escalations / avg minutes to first response
# Matches sql/corrected_queries.sql Q5: Chicago Q2 window on
# created_at_utc, status = 'OPEN' only (PENDING_POST excluded).
# RECONCILIATION.md 3.2 / 3.3 final row: 109 open, 48.8 min avg.
# ---------------------------------------------------------------------
print()
print("--- CQ5 True values ---")
all_ok &= check("Open escalations: 109 | avg min to first response: 48.8", """
SELECT
    COUNT(*),
    ROUND(AVG(EXTRACT(EPOCH FROM (e.first_response_at_utc - e.created_at_utc)) / 60.0), 1)
FROM escalation e
WHERE e.status = 'OPEN'
  AND e.created_at_utc >= TIMESTAMP '2026-04-01 05:00:00'
  AND e.created_at_utc <  TIMESTAMP '2026-07-01 05:00:00'
""", (109, 48.8))

print()
print("=== All verifications complete ===")
if not all_ok:
    print("One or more figures do NOT match RECONCILIATION.md. Investigate before submitting.")
    sys.exit(1)
else:
    print("All figures match RECONCILIATION.md.")