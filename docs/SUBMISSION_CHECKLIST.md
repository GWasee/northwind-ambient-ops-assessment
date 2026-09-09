# **Submission Checklist** 

Fill this in, commit it, and confirm every line before you submit. An unfilled checklist is treated as an incomplete submission.

**Candidate:** \_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_  **Date submitted:** \_\_\_\_\_\_\_\_\_\_\_\_  **Hours spent (honest):** \_\_\_\_\_\_

## Access

- [ ] Retool app shared with moontasir.abeer@commure.com  
- [ ] Retool app shared with [musfiqur.preo@commure.com](mailto:musfiqur.preo@commure.com)  
- [ ] A Retool **Release** version is tagged  
- [ ] GitHub repo accessible to both reviewers \- URL: \_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_  
- [ ] Video link (≤12 min, single take, screen \+ voice): \_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_

## Part 1 \- Reconciliation

- [ ] RECONCILIATION.md committed  
- [ ] Data profiling written up  
- [ ] Variance waterfall with per-correction quantification, for each headline metric  
- [ ] "The quarter" defined and defended  
- [ ] Decision A and Decision B answered in ≤400 words  
- [ ] Known unknowns stated  
- [ ] Number of defects I believe I found: \_\_\_\_\_\_

## Part 2 \- Triage Workbench

- [ ] Works at 1366×768, no vertical scroll on the primary pane (R1)  
- [ ] Interaction count per case: \_\_\_\_\_\_ (R2, math shown in UX\_RATIONALE.md)  
- [ ] Keyboard-only core loop, keymap documented (R3)  
- [ ] Selection / scroll / filters survive a refresh (R4)  
- [ ] Provenance panel shows the SLA target in force **on the note's date** (R5)  
- [ ] Empty, loading and error states designed; error state demoed in video (R6)  
- [ ] Explicit commit, optimistic, with visible rollback (R7)  
- [ ] Bulk action, safe to double-submit (R8)  
- [ ] Status survives greyscale; contrast ≥4.5:1 (R9)  
- [ ] Queue derived from my corrected logic (R10)  
- [ ] UX\_RATIONALE.md committed, including two rejected layouts and the requirement I did not fully satisfy

## Part 3 \- Recovery workflow

- [ ] Detection rule defined and justified, no hardcoded IDs (W1)  
- [ ] Posts to a real endpoint I control (W2) \- endpoint: \_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_  
- [ ] Idempotent across 5 runs, demonstrated in video (W3)  
- [ ] Rate limit ≤1 rps with jitter; exponential backoff on 429/5xx (W4)  
- [ ] Dead-letter path after N attempts, N justified (W5)  
- [ ] Safe to run concurrently; guard explained (W6)  
- [ ] Audit trail table designed by me; DDL in repo, keys/types/indexes justified (W7)  
- [ ] Reconciliation query proving zero stranded, zero duplicates (W8)

## Part 4 \- Practice

- [ ] Commits span ≥2 calendar days  
- [ ] ≥1 PR with my own review comments  
- [ ] JS lives in the repo as versioned modules, imported into Retool  
- [ ] Tests green in GitHub Actions \- covering TZ boundary, dedupe, effective-dated lookup, idempotency key  
- [ ] ≤3 ADRs in docs/adr/  
- [ ] DECISIONS.md \- stakeholder conflict identified and resolved  
- [ ] AI\_USAGE.md \- including one instance where I overrode AI output  
- [ ] README answers "what is wrong with this assessment?" (≤150 words)

## Declaration

- [ ] Every number in my written deliverables is reproducible from a query in this repo.  
- [ ] AI\_USAGE.md is complete and accurate.  
- [ ] This is my own work and I can explain and modify any part of it live.

