# AI Usage

This note records where AI was used on this assessment, for what, and one case where generated output was rejected and rewritten. Human review, query execution, and design decisions remain mine. Every figure cited in `docs/RECONCILIATION.md` is still required to come from a named query in `sql/corrected_queries.sql`.

## Platforms


| Platform                    | Role on this project                                                                                                                                                                                           |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **ChatGPT, Gemini, Claude** | Primary collaborator for SQL drafts, variance waterfalls, Retool query/JS troubleshooting, recovery-workflow code, stakeholder-conflict writeups, and first-pass documentation.                                |
| **Cursor**                  | In-repo collaborator for the same workstreams once files existed: query repair against PostgreSQL, Python verification (`verify.py`), Retool query/JS, and production of `docs/` artifacts from the live tree. |


Both tools were used as assistants, not as an unattended pipeline. I supplied schema, data-dictionary constraints, stakeholder text, and failing error messages; I ran the SQL; I kept or discarded the result.

## Where it was used



### 1. SQL engineering (Parts 1 and 2)

Used both platforms to draft and then revise PostgreSQL for:

- Canonical note grain (`note_id` is not unique; re-ingestions must be collapsed before any join).
- Void exclusion and Chicago business-date windows (`submitted_at_utc` interpreted in `America/Chicago`, not naive UTC midnight).
- Rubric composite recompute from raw dimension scores and the audit’s recorded `rubric_version`.
- Effective-dated `sla_config` lookup `(product_line, priority, effective period)` rather than current-row-only or unconstrained product/priority joins.
- Queue and provenance queries used by the Retool workbench (`sql/UI/`).

Typical failure modes I had to correct after generation: missing `::numeric` before `ROUND`, joining `clinician` as if it were type-1, grouping MDS leaderboards by `mds_name`, and treating `PERCENTILE_CONT` output as already rounded.

### 2. Reconciliation and metric waterfalls (Part 1)

Used AI to structure the step sequence in `docs/RECONCILIATION.md`: reported figure → one correction per row → CQ output. I used it to compare original vs corrected logic and to draft SQL that isolates each variance (duplicate-join fan-out, wrong reporting population, stored vs recomputed pass/fail). Intermediate waterfall rows were not accepted on narrative alone; they had to be runnable.

### 3. Automated verification

Used Cursor to draft and patch Python that executes `corrected_queries.sql` against the replica and verifies the documented headline numbers. The scripts are a check that the markdown did not drift from the SQL; they are not a substitute for reading the grain errors.

### 4. Operational model and Retool workbench (Part 2)

Used ChatGPT, then Cursor, for code only:

- Draft DDL for triage state and audit tables (keys, types, indexes, record versions).
- Queue, KPI, and provenance SQL used by the workbench.
- JavaScript for commit/undo.

Workbench layout, keyboard map, interaction count, and screen composition were designed without AI.

### 5. Recovery workflow (Part 3)

Used both platforms for implementation code: webhook posting, idempotency keys, retry/backoff handling, concurrency guards, and recovery audit SQL. Generated “just retry the same payload” snippets were rewritten so a second run cannot create a second escalation for the same stranded case. Workflow block layout and the recovery procedure itself were not AI-designed.

### 6. Requirements and documentation

Used both platforms to check drafts against the brief, name stakeholder conflicts (immediate row action vs deliberate confirm; full-queue-on-one-screen vs 2,500-row Monday backlog), and to write `docs/RECONCILIATION.md`, `docs/UX_RATIONALE.md`, ADRs, and this file. Prose was edited for claims that only the queries can support.

## Concrete override

**Generated output (rejected):** treat `note_id` as unique in this extract. The first `RECONCILIATION.md` draft (AI-assisted profiling) stated that both `ingestion_id` and `note_id` were unique here, that no duplicate ingestions existed in the dataset, and that uniqueness was only a *future* risk. The waterfall therefore never collapsed re-ingestions. True audited notes were reported as **1,583**.

**Why it was wrong:** the `note` grain is one row per *ingestion*, not per logical note. A uniqueness check that only looked at “does `note_id` look unique at a glance” missed 62 `note_id`s that each have two physical rows (6,235 rows, 6,173 distinct `note_id`s). Those pairs share `submitted_at_utc` and differ on `ingestion_id` / `ingested_at_utc`. Joining `note_audit` to `note` on `note_id` without collapsing them silently doubles every audited duplicate — 17 of the 62 are audited — with no error and no obviously wrong value.

**What I kept:** reject the uniqueness claim; resolve to one logical note before any join (`canonical_note`: latest `ingested_at_utc`, tie-break `ingestion_id`). That is the first waterfall step in the final `docs/RECONCILIATION.md`:


| Version     | `note_id` finding                                                              | Audited-note true value |
| ----------- | ------------------------------------------------------------------------------ | ----------------------- |
| First draft | Unique in this extract; no re-ingestions found; no `canonical_note` step       | 1,583                   |
| Final       | 62 duplicated `note_id`s; 17 audited doubles removed as step 1 (1,705 → 1,688) | **1,566**               |


**Reasoning:** the dictionary already allowed re-ingestion; the replica just happened to contain it. Accepting the generated “unique here, guard only for later” write-up would have left a grain error in every corrected query and understated how far Appendix A was from the true audited count (−122 vs the actual −139). I re-profiled `note` by `note_id` count, then made `canonical_note` mandatory in `sql/corrected_queries.sql` rather than a documented-but-unneeded precaution.