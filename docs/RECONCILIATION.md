# Part 1: Reconciliation and data judgment

Reproducibility guarantee. Every figure in this document is the direct output of a
named query in sql/corrected_queries.sql. Run any numbered query (CQ1,
CQ2, …) against the loaded tables to reproduce the corresponding figure.

---

## 3.1 Data Profiling

Before evaluating the provided reporting queries, I profiled each source table to establish its actual grain, key behaviour, duplicate risk, and effective dating semantics. This matters because the replica intentionally has no primary keys, foreign keys, or indexes, so uniqueness cannot be inferred from the physical schema.

### Table profile


| Table           | Rows  | Intended grain                                          | Actual key behaviour / finding                                                                                                                                                                                                                                     |
| --------------- | ----- | ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `note`          | 6,235 | One row per note ingestion                              | `ingestion_id` is unique. `note_id` is **not** unique here: 62 note_ids carry two ingestion rows apiece (6,235 rows over 6,173 distinct note_ids). Reporting logic must resolve to one row per note_id before joining anywhere downstream, or every join fans out. |
| `note_audit`    | 1,780 | One row per audit                                       | `audit_id` is unique. Each audited `note_id` appears once in this extract. The raw seven dimension scores are authoritative; `composite_score` and `pass_fail` are derived fields and therefore require validation rather than blind trust.                        |
| `clinician`     | 64    | One row per clinician per SCD2 version                  | Only 60 distinct clinicians exist. Four clinician IDs have historical and current versions, producing 64 physical rows. Joining on `clinician_id` alone therefore creates one-to-many fan-out.                                                                     |
| `mds`           | 34    | One row per documentation specialist                    | `mds_id` is the stable identifier. `mds_name` is not unique: Domingo, Rafael occurs for both MD-206 and MD-227. A leaderboard grouped by name can therefore merge two different specialists.                                                                       |
| `rubric_weight` | 14    | One row per rubric version per scoring dimension        | Seven dimensions exist for each of two rubric versions. Rubric version is material because both weights and the pass threshold change by version.                                                                                                                  |
| `sla_config`    | 8     | One row per product line, priority and effective period | Product line and priority alone are not a complete key. Two effective periods exist per (product_line, priority), so historical notes must be matched to the SLA target in force on the relevant business date.                                                    |
| `escalation`    | 533   | One row per escalation                                  | Escalation state includes OPEN, RESOLVED, and PENDINGPOST. PENDINGPOST represents a row that has not yet completed Slack posting and should not automatically be interpreted as a genuinely open human triage case.                                                |




### Material profiling findings



#### 1. `note_id` is not unique, and the fan-out it causes is exactly the kind of error that hides in an aggregate

62 note_ids have two ingestion rows (same `note_id`, same `submitted_at_utc`, different `ingestion_id`/`ingested_at_utc`), all non-void. A query that joins `note_audit` to `note` on `note_id` without first resolving to one canonical ingestion per note silently doubles the row for every one of those 17 note_ids that also happen to be audited — inflating any downstream count by exactly that fan-out, with no error, no null, and no obviously wrong value. `canonical_note` (latest `ingested_at_utc`, tie-broken by `ingestion_id`) is applied before every join in `corrected_queries.sql` for this reason.

#### 2. `clinician` is a true SCD2 dimension

The `clinician` table contains 64 rows for only 60 clinician IDs. Four clinicians have both historical and current records. A join such as `JOIN clinician c ON c.clinician_id = n.clinician_id` does not preserve note grain for those clinicians and duplicates downstream note and audit rows unless the appropriate effective record is selected — or the join is dropped entirely where clinician attributes aren't needed for the metric. This is a material risk because aggregate counts and rates can be distorted without any obvious SQL error.

#### 3. MDS names cannot be used as identifiers

`mds_name` is explicitly non-key data, and the supplied data demonstrates why. MD-206 and MD-227 are both named Domingo, Rafael. Any leaderboard or coaching decision grouped by `mds_name` instead of `mds_id` risks combining two different employees — see 3.4 for the concrete case this produces in this dataset.

#### 4. Audit outputs contain derived fields, and roughly one in six v2 audits has a defective derivation

The seven `score_*` columns in `note_audit` are the raw audit record. `composite_score` and `pass_fail` are derived by ETL using the rubric configuration. Recomputing every v2-rubric audit (929 rows) from its raw scores and the correct v2 weights shows that 779 rows match the stored `composite_score` exactly, but 150 rows (16.1% of v2 audits) match a composite computed with the weights for `hpi` and `ros` silently dropped and not renormalized — i.e., the stored figure for those 150 rows is wrong, not just rounded differently. The defect is spread across 32 of the 34 v2 auditors and across every week from rubric cutover (2026-05-15) onward, so it reads as an intermittent scoring-service defect, not a one-time migration event or an auditor-specific pattern. 143 of those 150 rows flip from PASS to FAIL on correction; 91 flip from FAIL to PASS. Because rubric v2 took effect during Q2 and changed both weights and the pass threshold, these derived fields must be reconciled against the raw scores and the recorded `rubric_version` before they are used for a leadership decision.

#### 5. SLA configuration is effective dated

`sla_config` contains historical configuration rows. The lookup key is not merely `(product_line, priority)` but `(product_line, priority, effective period)`. A query that joins only on product line and priority matches **both** periods for every note (there is no gap or overlap between them), silently doubling the joined population, and a query that joins only to the current (`effective_to IS NULL`) row applies today's tighter SLA retrospectively to notes governed by the old target.

#### 6. Escalation status has operational semantics beyond “open or closed”

`PENDING_POST` is not equivalent to `OPEN`. The data dictionary states that the escalation row is written first, Slack is posted second, and the Slack thread reference is populated only after posting succeeds. I therefore treat `PENDING_POST` as a delivery/workflow state that requires separate reconciliation (see Part 3) rather than including it automatically in the count of genuine open escalations.

### Profiling conclusion

The largest structural risks are not missing rows or malformed types. They are grain and effective-dating errors: note re-ingestion fan-out, SCD2 clinician fan-out, reliance on a derived audit field with a real 16%-incidence defect, non-unique MDS names, and historical SLA configuration. These are precisely the kinds of issues that can produce plausible operational metrics while changing the business decision behind them.

---



## 3.2 True Values


| Metric                    | Reported (Appendix A) | True Value           | Delta   |
| ------------------------- | --------------------- | -------------------- | ------- |
| Audited notes (Q2)        | 1,705                 | **1,566**            | −139    |
| Pass rate                 | 79.9%                 | **76.8%**            | −3.1 pp |
| Avg composite score       | 0.9055                | **0.9161**           | 0.0106  |
| SLA breach rate           | 12.8%                 | **10.4%**            | −2.4 pp |
| Median delivery (min)     | 18.5                  | **18.1**             | −0.4    |
| Notes measured for SLA    | 296                   | **5,449**            | 5,153   |
| Open escalations          | 149                   | **109**              | −40     |
| Avg min to first response | 49.5                  | **48.8**             | −0.7    |
| Anomaly weekdays flagged  | 28 of 91 days         | **2 of 65 weekdays** | −26     |


> **Source:** Run `CQ1` through `CQ5` in `sql/corrected_queries.sql` to reproduce every figure above.



### "The Quarter" — Definition and Defence



#### Authoritative definition

**Q2 FY26  2026-04-01 through 2026-06-30, inclusive, America/Chicago business day.**

The data dictionary states: *"Operational reporting, staffing, and every commitment we make to a client is stated in the America/Chicago business day."*

On all dates in Q2 2026, Chicago observes **CDT (Central Daylight Time  UTC−5)**. DST began 2026-03-08 and ends 2026-11-01; no DST boundary falls inside Q2.


| Boundary                            | Chicago local           | UTC equivalent              |
| ----------------------------------- | ----------------------- | --------------------------- |
| Quarter start                       | 2026-04-01 00:00:00 CDT | **2026-04-01 05:00:00 UTC** |
| Quarter end (inclusive)             | 2026-06-30 23:59:59 CDT | 2026-07-01 04:59:59 UTC     |
| Quarter end (exclusive upper bound) | 2026-07-01 00:00:00 CDT | **2026-07-01 05:00:00 UTC** |


**SQL expression used in every corrected query:**

```sql
WHERE submitted_at_utc >= TIMESTAMP '2026-04-01 05:00:00'   -- inclusive
  AND submitted_at_utc <  TIMESTAMP '2026-07-01 05:00:00'   -- exclusive
```



#### Why the provided queries get it wrong

The provided queries use:

```sql
WHERE n.submitted_at_utc BETWEEN TIMESTAMP '2026-04-01' AND TIMESTAMP '2026-06-30'
```

`TIMESTAMP '2026-04-01'` resolves to `2026-04-01 00:00:00 UTC`. `TIMESTAMP '2026-06-30'` resolves to `2026-06-30 00:00:00 UTC`.

- **Wrongly included:** 4 notes submitted 2026-04-01 00:00–04:59 UTC, which were actually submitted on **March 31 in Chicago** and belong to Q1.
- **Wrongly excluded:** 81 notes submitted 2026-06-30 05:00 UTC through 2026-07-01 04:59 UTC, which were submitted on **June 30 in Chicago** and belong to Q2.
- **Net effect on the note pool:** 1 note vs the Chicago-correct window (the naive window happens to include 4 and exclude 81 others, plus the June 30 end-of-day cut adds 86 more to the Chicago window vs the midnight-only upper bound).

The Chicago window yields **5,590 Q2 notes** (5,510 non-voided). The naive window yields 5,589.

The same boundary bug is why the naive daily-volume query in 3.3 silently drops 2026-06-30 entirely — the naive window contains no rows for that calendar day at all.

---



## 3.3 Variance Waterfall

Each table below walks from the literal reported figure to the CQ output, one correction per row, in the order the fix is applied in `corrected_queries.sql`. Every intermediate row is itself a runnable query (available in `sql/waterfall_queries.sql`) — this is not a two-point "before/after" with the middle asserted.

### Audited notes / pass rate / avg composite score (→ CQ1)


| #   | Correction applied                                                                                  | Notes                                                                                                                                                        | Audited notes | Δ notes  | Pass rate | Δ pass rate | Avg composite | Δ composite |
| --- | --------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------- | -------- | --------- | ----------- | ------------- | ----------- |
| 0   | Reported figure                                                                                     | Naive `note_id` join (no dedup), naive UTC window, includes voided notes, joins `clinician` without SCD2 filter, trusts stored `composite_score`/`pass_fail` | 1,705         | —        | 79.9%     | —           | 0.9055        | —           |
| 1   | Resolve note re-ingestions to one logical note (`canonical_note`)                                   | Removes double-counting for the 17 audited note_ids that were re-ingested                                                                                    | 1,688         | −17      | 79.9%     | 0.0 pp      | 0.9054        | −0.0001     |
| 2   | Switch to the America/Chicago Q2 window                                                             | Excludes 4 late-March notes wrongly pulled in by the naive UTC window; includes June 30 notes wrongly excluded by it                                         | 1,712         | +24      | 79.8%     | −0.1 pp     | 0.9048        | −0.0006     |
| 3   | Exclude voided notes                                                                                | A voided note is not a delivered unit of work per the data dictionary                                                                                        | 1,694         | −18      | 79.8%     | 0.0 pp      | 0.9045        | −0.0003     |
| 4   | Remove the unnecessary clinician SCD2 join                                                          | Drops the fan-out from the 4 clinicians with historical + current records                                                                                    | 1,566         | −128     | 79.6%     | −0.2 pp     | 0.9043        | −0.0002     |
| 5   | Recompute `composite_score`/`pass_fail` from raw scores using the audit's recorded `rubric_version` | Fixes the 150-row hpi/ros-dropped-weight ETL defect (3.1, finding 4)                                                                                         | 1,566         | 0        | **76.8%** | **−2.8 pp** | **0.9161**    | **+0.0118** |
|     | **Total**                                                                                           |                                                                                                                                                              | **1,566**     | **−139** | **76.8%** | **−3.1 pp** | **0.9161**    | **+0.0106** |


The single largest correction to the audited-note *count* is the clinician join removal (−128 notes, from an unrelated fan-out that has nothing to do with audit quality). The single largest correction to the *pass rate* is the composite recompute (−2.8 pp) — and it moves the number in the direction that makes the problem look worse, not better. Steps 1–4 net out to roughly flat on pass rate (they mostly change which notes are in the denominator, not the truth of any individual audit); step 5 is where the real finding is.

### SLA breach rate / median delivery / notes measured (→ CQ2)


| #   | Correction applied                                                                                         | Notes                                                                                                                                                                                                                                  | Notes measured | Δ measured | Breach rate | Δ breach    | Median (min) | Δ median |
| --- | ---------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------- | ---------- | ----------- | ----------- | ------------ | -------- |
| 0   | Reported figure                                                                                            | Naive UTC window, no dedup, no void/delivery filter, `sla_config` joined on `(product_line, priority)` only (both effective periods match, doubling rows), restricted to notes with an escalation whose status is OPEN or PENDING_POST | 296            | —          | 12.8%       | —           | 18.5         | —        |
| 1   | Resolve note re-ingestions                                                                                 | Removes 2 double-counted rows among the escalated population                                                                                                                                                                           | 294            | −2         | 12.9%       | +0.1 pp     | 18.5         | 0.0      |
| 2   | Switch to the America/Chicago Q2 window                                                                    | No escalated note in this subset straddles the boundary                                                                                                                                                                                | 294            | 0          | 12.9%       | 0.0 pp      | 18.5         | 0.0      |
| 3   | Exclude voided and undelivered notes                                                                       | Drops 2 more rows                                                                                                                                                                                                                      | 292            | −2         | 13.0%       | +0.1 pp     | 18.5         | 0.0      |
| 4   | Match `sla_config` on the effective period in force on the note's Chicago business date                    | Collapses the double-count from matching both SLA periods per note — population exactly halves                                                                                                                                         | 146            | −146       | 14.4%       | +1.4 pp     | 18.5         | 0.0      |
| 5   | Remove the escalation join/filter (measure **every** delivered, non-void Q2 note, not just escalated ones) | This is the dominant defect: the reported query only ever measured the ~3% of notes that had already been escalated, which is a biased (worse-than-average) sample of delivery performance, not the whole population                   | **5,449**      | **+5,303** | **10.4%**   | **−4.0 pp** | **18.1**     | **−0.4** |
|     | **Total**                                                                                                  |                                                                                                                                                                                                                                        | **5,449**      | **+5,153** | **10.4%**   | **−2.4 pp** | **18.1**     | **−0.4** |


This is the pair of corrections mentioned in the brief that move a headline number in opposite directions: fixing the effective-dating bug alone (step 4) *raises* the apparent breach rate to 14.4%, because it stops applying the old (looser) SLA target retroactively and starts holding old notes to whichever target — old or current — was actually in force. It's only once the population is corrected in step 5, from "notes someone already escalated" to "every delivered note," that the breach rate falls to its true value of 10.4%. A reviewer who applied only the effective-dating fix and stopped there would have walked away with a *worse* headline number than the one being reported, on a *smaller and more biased* sample — the classic partial-fix trap the brief warns about.

### Open escalations / avg minutes to first response (→ CQ5)


| #   | Correction applied                      | Notes                                                                                                         | Open escalations | Δ count | Avg min to 1st response | Δ avg    |
| --- | --------------------------------------- | ------------------------------------------------------------------------------------------------------------- | ---------------- | ------- | ----------------------- | -------- |
| 0   | Reported figure                         | Naive UTC window on `created_at_utc`; counts status IN (OPEN, PENDING_POST) as "open"                         | 149              | —       | 49.5                    | —        |
| 1   | Switch to the America/Chicago Q2 window |                                                                                                               | 152              | +3      | 48.8                    | −0.7     |
| 2   | Count `status = 'OPEN'` only            | PENDING_POST is a posting/workflow state, not a human triage backlog item (3.1, finding 6; handled in Part 3) | **109**          | **−43** | **48.8**                | **0.0**  |
|     | **Total**                               |                                                                                                               | **109**          | **−40** | **48.8**                | **−0.7** |




### Daily volume anomaly flag (→ CQ3)


| #   | Correction applied                                                                                                | Notes                                                                                                                | Total days scored                                    | Days flagged |
| --- | ----------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- | ------------ |
| 0   | Reported figure                                                                                                   | UTC calendar date, no dedup, includes voided notes, no zero-volume day generated, flag applied to every calendar day | 90 (reported as "of 91," the nominal quarter length) | 28           |
| 1   | Resolve note re-ingestions                                                                                        | No effect on this metric — no re-ingested note's UTC date crosses a day boundary                                     | 90                                                   | 28           |
| 2   | Convert to the America/Chicago business date and window                                                           | Recovers 2026-06-30, which the naive UTC window drops entirely (0 rows that day under the naive filter)              | 91                                                   | 28           |
| 3   | Exclude voided notes                                                                                              | No effect — no day's flag status changes                                                                             | 91                                                   | 28           |
| 4   | Generate all 91 Q2 calendar dates so zero-volume days are retained                                                | No effect in this dataset — no calendar day other than the one fixed in step 2 has zero volume                       | 91                                                   | 28           |
| 5   | Apply the flag only to weekdays (weekends stay in the 14-day trailing baseline, but are never themselves flagged) | This is the entire correction                                                                                        | 91 total / **65 weekdays**                           | **2**        |


Steps 1, 3, and 4 are correct and defensible fixes, and each is independently reproducible — but none of them move this number. The naive alert was firing on ordinary weekend volume troughs 26 times out of 28. The two real anomalies, 2026-05-25 and 2026-06-19, are Memorial Day and Juneteenth — federal holidays, not operational incidents (see 3.5).

---



## 3.4 Business Decisions



### Decision A — $410K Q3 Remediation Program

> *Proposed: mandatory retraining for all MDS pods, audit coverage raised from 27% to 40%, one additional QA headcount.*

Yes, fund Decision A at its stated scope, but delay execution until two prerequisite conditions are met. The corrected data actually strengthens the case for intervention: the corrected pass rate is 76.8% against a 90% target, revealing a wider 13.2-point gap than the 10.1-point gap in the reported memo. Failures are broadly and evenly distributed across all four MDS pods (fail rates ranging from 21.2% to 26.3% with no outlier pod), which fully justifies a program touching every pod. Furthermore, the net loss of 52 additional failures (143 previously-PASS audits flipping to FAIL versus 91 flipping the other way) stems from recomputing `composite_score` from raw scores, as 16% of v2 audits silently dropped HPI and ROS. 

However, funding should be held until:   

1. **Curriculum Alignment:** The retraining curriculum is explicitly targeted at the specific raw dimensions that are failing (a breakdown not yet included in this analysis).
2. **ETL Bug Resolution:** The underlying ETL scoring defect is fixed and backfilled before expanding audit coverage from 27% to 40%, preventing the expansion from doubling the surface area of a live scoring bug.



### Decision B — Leaderboard Awards and 60-Day Coaching Plans

> *Proposed: quarterly recognition award to the top of the leaderboard; bottom five on a documented HR-tracked 60-day coaching plan.*

No, do not execute Decision B as currently specified, due to two independent flaws revealed in the data. 

1. **Inactive Specialist Inclusion:** MD-201 (Achebe, Noor) appears in the bottom five by corrected composite score (0.887) despite her `mds.status` being `INACTIVE`. Placing a departed specialist on a documented 60-day HR coaching plan is meaningless or unfair. This requires a query exclusion filter `mds.status = 'ACTIVE'`) rather than manual post-hoc corrections.
2. **Name Collision Merging:** Grouping the leaderboard by `mds_name` instead of `mds_id` merges distinct specialists who share a name (e.g., MD-206 and MD-227, both named "Domingo, Rafael") into a single blended score of 0.9151 across 338 notes. This masks MD-206's genuine bottom-five performance (0.903) behind MD-227's strong performance (0.926, rank #7).

**Net Action:** Prior to rollout, exclude inactive records and ensure the underlying query groups strictly by `mds_id`.

**SQL expression used to prove Decision B**

```sql
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
```

---



## 3.5 Known Unknowns

Things I did not check, and what I'd need to close them:

1. **Which physical ingestion an audit actually scored.** `note_audit` carries `note_id`, not `ingestion_id`. For the 17 audited note_ids with two non-void ingestions, I assumed the audit reflects the canonical (latest-ingested) version, matching the convention used everywhere else in this analysis. I have no way to confirm that from the data alone — I'd ask the audit tooling team whether the auditor reviews the note at the time of audit assignment (which could be the earlier ingestion) or always the current version.
2. **Root cause of the note re-ingestion itself.** The dictionary lists transcription retry, client resubmit, and backfill as causes, but doesn't say which applies to these 62 note_ids, or whether the content differs between ingestions (a genuine content correction) versus being a byte-identical replay. That distinction matters for whether "latest wins" is the right canonicalization rule or whether some other rule (e.g., first successful, or a content diff) would be more correct.
3. **Root cause of the 150-row hpi/ros scoring defect.** I can show it's not tied to a single auditor (32 of 34 v2 auditors are affected) and not a one-time migration event (it recurs every week from cutover through the most recent audits in the extract). I do not have access to the scoring service's code or logs, so I can't say whether it's a race condition, a caching bug, or a partial-deploy issue. This needs an engineering ticket, not a data fix — and until it's fixed, every new v2 audit has an estimated 16% chance of being scored wrong.
4. **Whether undelivered notes hide additional SLA breaches.** CQ2 requires `delivered_at_utc IS NOT NULL`, which is correct for "time to deliver" but silently excludes any note that was submitted and never delivered at all — arguably the worst possible SLA outcome. I did not quantify how many Q2 notes fall into this bucket or how old the oldest one is; that's a straightforward follow-up query but a business call on how to count it (a breach with infinite/unknown duration, or a separate metric entirely).
5. **The coaching-plan process for inactive staff.** I found the MD-201 case (3.4) but don't know HR's actual policy for a specialist who becomes inactive mid-quarter — whether performance data for their active period should still feed *someone's* review, or be excluded outright. I'd take that back to whoever owns the coaching-plan process rather than deciding it myself.
6. **Whether the two anomaly-flag days should be excluded from the model, not just left unflagged.** 2026-05-25 (Memorial Day) and 2026-06-19 (Juneteenth) are true volume troughs, correctly flagged as weekday anomalies under the corrected logic. Whether ops wants a holiday calendar baked into the baseline (so a real holiday never lights up the alert at all) or wants to see it and dismiss it manually is a product decision, not a data one — I left the alert firing on both.
7. **PENDING_POST volume and age, beyond what's needed for this document.** I excluded PENDING_POST from "open escalations" per the data dictionary's own framing, but I did not characterize how many PENDING_POST rows exist, how old the oldest one is, or whether any of them are actually stranded (created, never posted, never retried). That's the explicit subject of Part 3 and I left it there rather than duplicating the work here.
8. **Whether clinician-level cuts of any of these metrics are needed.** I removed the clinician join from CQ1 because it isn't needed for the metrics in this document and only introduces SCD2 fan-out risk. If a future request needs pass rate or SLA performance broken out by clinician region or employment status, the correct SCD2-safe join (`AND c.is_current_record` or an effective-date match, matching the sla_config pattern) still needs to be written and isn't exercised by anything in `corrected_queries.sql` today.

