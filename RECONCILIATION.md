# Part 1: Reconciliation and data judgment

> **Reproducibility guarantee.** Every figure in this document is the direct output of a named query in [`sql/corrected_queries.sql`](http://sql/corrected_queries.sql). Run any numbered query (`CQ1`, `CQ2`, …) against the loaded tables to reproduce the corresponding figure.

---

## 3.1 Data Profiling

Before evaluating the provided reporting queries, I profiled each source table to establish its actual grain, key behaviour, duplicate risk, and effective dating semantics. This matters because the replica intentionally has no primary keys, foreign keys, or indexes, so uniqueness cannot be inferred from the physical schema.

### Table profile

| Table | Rows | Intended grain | Actual key behaviour / finding |
| :---- | ----: | :---- | :---- |
| `note` | 6,235 | One row per note ingestion | `ingestion_id` is unique in the supplied data. `note_id` is also unique in this extract, although the data dictionary explicitly allows the same note to be re-ingested. Reporting logic therefore should not treat `note_id` uniqueness as a permanent contract. |
| `note_audit` | 1,780 | One row per audit | `audit_id` is unique. Each audited `note_id` appears once in this extract. The raw seven dimension scores are authoritative; `composite_score` and `pass_fail` are derived fields and therefore require validation rather than blind trust. |
| `clinician` | 64 | One row per clinician per SCD2 version | Only 60 distinct clinicians exist. Four clinician IDs have historical and current versions, producing 64 physical rows. Joining on `clinician_id` alone therefore creates one-to-many fan-out. |
| `mds` | 34 | One row per documentation specialist | `mds_id` is the stable identifier. `mds_name` is not unique: Domingo, Rafael occurs for both MD-206 and MD-227. A leaderboard grouped by name can therefore merge two different specialists. |
| `rubric_weight` | 14 | One row per rubric version per scoring dimension | Seven dimensions exist for each of two rubric versions. Rubric version is material because both weights and the pass threshold change by version. |
| `sla_config` | 8 | One row per product line, priority and effective period | Product line and priority alone are not a complete key. Two effective periods exist, so historical notes must be matched to the SLA target in force on the relevant business date. |
| `escalation` | 533 | One row per escalation | Escalation state includes OPEN, RESOLVED, and PENDING\_POST. PENDING\_POST represents a row that has not yet completed Slack posting and should not automatically be interpreted as a genuinely open human triage case. |

### Material profiling findings

#### 1\. clinician is a true SCD2 dimension

The `clinician` table contains 64 rows for only 60 clinician IDs. Four clinicians have both historical and current records. A join such as:

JOIN clinician c

  ON c.clinician\_id \= n.clinician\_id

does not preserve note grain for those clinicians. It can duplicate downstream note and audit rows unless the appropriate effective record is selected. This is a material risk because aggregate counts and rates can be distorted without any obvious SQL error.

#### 2\. note\_id is unique here, but that is not the documented grain

The `note` table is documented as one row per ingestion, not one row per logical note. In the supplied extract, both `ingestion_id` and `note_id` happen to be unique. I therefore found no duplicate note ingestion in this dataset, but I would not encode that accidental uniqueness as a reporting assumption. A replay or backfill could legitimately create multiple rows for one `note_id`.

#### 3\. MDS names cannot be used as identifiers

`mds_name` is explicitly non-key data, and the supplied data demonstrates why. MD-206 and MD-227 are both named Domingo, Rafael. Any leaderboard or coaching decision grouped by `mds_name` instead of `mds_id` risks combining two different employees.

#### 4\. Audit outputs contain derived fields

The seven `score_*` columns in `note_audit` are the raw audit record. `composite_score` and `pass_fail` are derived by ETL using the rubric configuration. Because rubric v2 took effect during Q2 and changed both weights and the pass threshold, these derived fields must be reconciled against the raw scores and the recorded `rubric_version` before they are used for a leadership decision.

#### 5\. SLA configuration is effective dated

`sla_config` contains historical configuration rows. The lookup key is not merely `(product_line, priority)` but `(product_line, priority, effective period)`. A query that joins only on product line and priority can match multiple SLA rows or apply today’s SLA retrospectively to historical notes.

#### 6\. Escalation status has operational semantics beyond “open or closed”

`PENDING_POST` is not equivalent to `OPEN`. The data dictionary states that the escalation row is written first, Slack is posted second, and the Slack thread reference is populated only after posting succeeds. I therefore treat `PENDING_POST` as a delivery/workflow state that requires separate reconciliation rather than including it automatically in the count of genuine open escalations.

### Profiling conclusion

The largest structural risks are not missing rows or malformed types. They are grain and effective-dating errors: SCD2 clinician fan-out, reliance on derived audit fields, non-unique MDS names, and historical SLA configuration. These are precisely the kinds of issues that can produce plausible operational metrics while changing the business decision behind them.

---

## 3.2 True Values

| Metric | Reported (Appendix A) | True Value | Delta |
| :---- | ----: | ----: | ----: |
| Audited notes (Q2) | 1,705 | **1,583** | −122 |
| Pass rate | 79.9% | **76.7%** | −3.2 pp |
| Avg composite score | 0.9055 | **0.9162** | \+0.0107 |
| SLA breach rate | 12.8% | **10.3%** | −2.5 pp |
| Median delivery (min) | 18.5 | **18.1** | −0.4 |
| Notes measured for SLA | 296 | **5,510** | \+5,214 |
| Open escalations | 149 | **109** | −40 |
| Avg min to first response | 49.5 | **48.8** | −0.7 |
| Anomaly weekdays flagged | 28 of 91 days | **2 of 65 weekdays** | −26 |

> **Source:** Run `CQ1` through `CQ5` in `sql/corrected_queries.sql` to reproduce every figure above.

## "The Quarter" — Definition and Defence

### Authoritative definition

**Q2 FY26 \= 2026-04-01 through 2026-06-30, inclusive, America/Chicago business day.**

The data dictionary states: *"Operational reporting, staffing, and every commitment we make to a client is stated in the America/Chicago business day."*

On all dates in Q2 2026, Chicago observes **CDT (Central Daylight Time \= UTC−5)**. DST began 2026-03-08 and ends 2026-11-01; no DST boundary falls inside Q2.

| Boundary | Chicago local | UTC equivalent |
| :---- | :---- | :---- |
| Quarter start | 2026-04-01 00:00:00 CDT | **2026-04-01 05:00:00 UTC** |
| Quarter end (inclusive) | 2026-06-30 23:59:59 CDT | 2026-07-01 04:59:59 UTC |
| Quarter end (exclusive upper bound) | 2026-07-01 00:00:00 CDT | **2026-07-01 05:00:00 UTC** |

**SQL expression used in every corrected query:**

WHERE submitted\_at\_utc \>= TIMESTAMP '2026-04-01 05:00:00'   \-- inclusive

  AND submitted\_at\_utc \<  TIMESTAMP '2026-07-01 05:00:00'   \-- exclusive

### Why the provided queries get it wrong

The provided queries use:

WHERE n.submitted\_at\_utc BETWEEN TIMESTAMP '2026-04-01' AND TIMESTAMP '2026-06-30'

`TIMESTAMP '2026-04-01'` resolves to `2026-04-01 00:00:00 UTC`. `TIMESTAMP '2026-06-30'` resolves to `2026-06-30 00:00:00 UTC`.

- **Wrongly included:** 4 notes submitted 2026-04-01 00:00–04:59 UTC, which were actually submitted on **March 31 in Chicago** and belong to Q1.  
- **Wrongly excluded:** 81 notes submitted 2026-06-30 05:00 UTC through 2026-07-01 04:59 UTC, which were submitted on **June 30 in Chicago** and belong to Q2.  
- **Net effect on the note pool:** \+1 note vs the Chicago-correct window (the naive window happens to include \+4 and exclude 81 others, plus the June 30 end-of-day cut adds 86 more to the Chicago window vs the midnight-only upper bound).

The Chicago window yields **5,590 Q2 notes** (5,510 non-voided). The naive window yields 5,589.  
---

## 3.4 Variance Waterfall

---

## 3.5 Business Decisions

### Decision A — $410K Q3 Remediation Program

> *Proposed: mandatory retraining for all MDS pods, audit coverage raised from \~27% to 40%, one additional QA headcount.*

### Decision B — Leaderboard Awards and 60-Day Coaching Plans

> *Proposed: quarterly recognition award to the top of the leaderboard; bottom five on a documented HR-tracked 60-day coaching plan.*

---

## 3.6 Known Unknowns

