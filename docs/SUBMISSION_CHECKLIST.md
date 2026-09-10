# **Submission Checklist**

Fill this in, commit it, and confirm every line before you submit. An unfilled checklist is treated as an incomplete submission.

**Candidate: Mustafa Alaff Wasee**   **Date submitted:**   **Hours spent (honest):** Implementation (8hr 15mins), Research & Prompting (5hrs)

## Access

- [x] Retool app shared with [moontasir.abeer@commure.com](mailto:moontasir.abeer@commure.com)  
- [x] Retool app shared with [musfiqur.preo@commure.com](mailto:musfiqur.preo@commure.com)  
- [x] A Retool **Release** version is tagged  
- [x] GitHub repo accessible to both reviewers  URL:   
- [x] Video link (≤12 min, single take, screen  voice): 



## Part 1  Reconciliation

- [x] RECONCILIATION.md committed  
- [x] Data profiling written up  
- [x] Variance waterfall with per-correction quantification, for each headline metric  
- [x] "The quarter" defined and defended  
- [x] Decision A and Decision B answered in ≤400 words  
- [x] Known unknowns stated  
- [x] Number of defects I believe I found: 



## Part 2  Triage Workbench

- [x] Works at 1366×768, no vertical scroll on the primary pane (R1)  
- [x] Interaction count per case:  (R2, math shown in UXRATIONALE.md)  
- [x] Keyboard-only core loop, keymap documented (R3)  
- [x] Selection / scroll / filters survive a refresh (R4)  
- [x] Provenance panel shows the SLA target in force **on the note's date** (R5)  
- [x] Empty, loading and error states designed; error state demoed in video (R6)  
- [x] Explicit commit, optimistic, with visible rollback (R7)  
- [ ] Bulk action, safe to double-submit (R8)  
- [x] Status survives greyscale; contrast ≥4.5:1 (R9)  
- [x] Queue derived from my corrected logic (R10)  
- [x] UXRATIONALE.md committed, including two rejected layouts and the requirement I did not fully satisfy



## Part 3  Recovery workflow

- [x] Detection rule defined and justified, no hardcoded IDs (W1)  
- [x] Posts to a real endpoint I control (W2)  endpoint:   
- [x] Idempotent across 5 runs, demonstrated in video (W3)  
- [x] Rate limit ≤1 rps with jitter; exponential backoff on 429/5xx (W4)  
- [ ] Dead-letter path after N attempts, N justified (W5)  
- [ ] Safe to run concurrently; guard explained (W6)  
- [x] Audit trail table designed by me; DDL in repo, keys/types/indexes justified (W7)  
- [x] Reconciliation query proving zero stranded, zero duplicates (W8)



## Part 4  Practice

- [x] Commits span ≥2 calendar days  
- [x] ≥1 PR with my own review comments  
- [ ] JS lives in the repo as versioned modules, imported into Retool  
- [ ] Tests green in GitHub Actions  covering TZ boundary, dedupe, effective-dated lookup, idempotency key  
- [x] ≤3 ADRs in docs/adr/  
- [x] DECISIONS.md  stakeholder conflict identified and resolved  
- [x] AIUSAGE.md  including one instance where I overrode AI output  
- [x] README answers "what is wrong with this assessment?" (≤150 words)



## Declaration

- [x] Every number in my written deliverables is reproducible from a query in this repo.  
- [x] AIUSAGE.md is complete and accurate.  
- [x] This is my own work and I can explain and modify any part of it live.