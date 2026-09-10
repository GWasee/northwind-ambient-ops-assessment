# Northwind Ambient Ops — BI Technical Assessment

Reconciliation of leadership's Q2 FY26 operational reporting, a single-screen Retool
triage workbench, and a recovery workflow for stranded escalations. Full findings
live in `docs/`.

---

## 1. Repository structure

```
.
├── README.md                          # This file
├── LICENSE
├── docs/
│   ├── RECONCILIATION.md              # Part 1 — profiling, waterfalls, Decision A/B, known unknowns
│   ├── UX_RATIONALE.md                # Part 2 — time-on-task budget, interaction count, keymap, rejected layouts
│   ├── DECISIONS.md                   # Part 4.5 — stakeholder conflict (R-01 vs R-02), resolution and trade-off
│   ├── AI_USAGE.md                    # Part 4.6 — where AI was used, and one rejected/corrected output
│   ├── SUBMISSION_CHECKLIST.md        # Filled in immediately before submission
│   └── adr/                           # Up to 3 Architecture Decision Records
├── sql/
│   ├── corrected_queries.sql          # CQ1–CQ5: the corrected, standalone reporting queries
│   ├── waterfall_queries.sql          # One runnable query per waterfall row in RECONCILIATION.md
│   └── UI/
│       ├── get_triage_view.sql        # ops.triage_queue_view — canonical queue + provenance logic
│       ├── get_queue_counts.sql       # KPI counts consumed by the workbench header
│       ├── get-case-details.sql       # Selected-case detail + 7 raw audit sub-scores
│       └── get-case-provenance.sql    # "Why is this case in the queue" panel
└── verify.py                          # (Part 4.3) executes corrected_queries.sql against the replica
                                         and checks output against the documented headline numbers
```

> Every number in `docs/RECONCILIATION.md` is the direct output of a named query in
> `sql/corrected_queries.sql`. Run `CQ1`–`CQ5` against the loaded tables to reproduce
> every figure.

---



## 2. What's wrong with this assessment

*(Required, ≤150 words — reproduced from the assessment README)*

It measures whether I can find grain errors and ship a keyboard-operable Retool app
under 10 hours, which is real but narrow. It doesn't test how I'd behave when a fix
has a cost — e.g., telling a director their headline metric is unreliable, or that a
"quick win" bulk action risks a physician-facing mistake — under real organizational
pressure rather than a take-home's absence of it. It also can't observe how I
collaborate: whether I'd actually go ask the QA Lead the clarifying question I wrote
down, or just proceed on my best guess, as I did here. I'd have liked a short
live exercise where a stakeholder pushes back on a finding in real time, to see
whether the reconciliation holds up under argument, not just under a SQL runner.

---



## 3. Reproducing the numbers

```bash
# Load the seven CSVs into Postgres (or Retool DB) using schema.sql, then:
psql -f sql/corrected_queries.sql
psql -f sql/UI/get_triage_view.sql
psql -f sql/UI/get_queue_counts.sql

# Or validate locally first with DuckDB:
python verify.py
```

Every figure in `docs/RECONCILIATION.md` should match the output of the
corresponding `CQ*` query exactly.