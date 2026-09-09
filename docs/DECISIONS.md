## Decision: Require deliberate confirmation before committing a disposition

**Decision:** I chose an explicit confirmation step over completion through a single row click.

**Scope:** The single-case triage disposition flow. This resolves the conflicting action requests in Appendix B, R-01 and R-02.

---

### The Conflicting Requests


| Stakeholder            | Request                                                                                   | Implication                                                                             |
| ---------------------- | ----------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| **Ops Director, R-01** | Complete the decision with “one click, straight from the table.”                          | The row click would immediately commit the disposition without a separate confirmation. |
| **QA Lead, R-02**      | “anything that changes a clinician-facing record needs a deliberate second confirmation.” | The operator must separately confirm the intended change before it is committed.        |


These requests cannot both be satisfied for the same action when it changes a clinician-facing record. If the row click completes the change immediately, there is no second confirmation. If the change waits for confirmation, the row click has not completed it.

QA also gives a concrete reason for the safeguard: accidental dispositions previously caused problems with a physician group. The assessment independently resolves the row-selection question through Part 2, R7, which requires explicit commitment and states that row-click alone must not mutate anything.

---



### Who I Would Go Back To and What I Would Ask

I would bring the Ops Director and QA Lead together to agree on the boundary between fast navigation and deliberate commitment.


| Stakeholder      | Specific Questions                                                                                                                                                                                                                                                        |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Ops Director** | “Would disposition and reason shortcuts followed by a keyboard confirmation meet your need for speed? Is the main problem the extra input, or having to find and reach a Save button?”                                                                                    |
| **QA Lead**      | “Which of Approve, Reject and Escalate changes a clinician-facing record? Would a separate confirmation showing the selected case, proposed disposition and reason satisfy your safeguard? What additional information, if any, must the operator see before confirming?” |


> *These are proposed stakeholder questions. I am not representing this consultation as having happened or claiming that either stakeholder has approved the design. My chosen flow retains confirmation while those details are clarified.*

---



### What I Chose

I chose a consistent, explicit confirmation step for the single-case disposition flow documented in `UX_RATIONALE.md`.

1. **Row Selection:** Selecting a row opens the case for inspection and does not commit a state change.
2. **Preparation:** Selecting a disposition and reason prepares the proposed decision.
3. **Commit Command:** The commit command opens a confirmation showing the selected case, proposed disposition, and reason.
4. **Explicit Confirmation:** A separate affirmative input confirms the change. Opening the confirmation must not also accept it. Cancelling leaves the persisted case state unchanged.

The confirmation must be keyboard-operable so that it preserves the intent of the Ops Director’s R-05 request. After final confirmation, the commit follows assessment R7: the UI reflects the pending change optimistically and visibly rolls it back if persistence fails.

This is the chosen behaviour. The existing UX document supports the direction through its “Enter: Commit with confirmation modal” keymap entry; it does not, by itself, verify every behaviour above.

---



### Why I Chose It and What I Gave Up

I prioritised deliberate commitment because QA identified a previous operational failure and the assessment expressly forbids mutation through row selection alone. Keyboard access addresses the Ops Director’s concern about finding a Save button while preserving a distinct confirmation action.

**What I gave up:** I gave up the Ops Director’s literal request for completion through a single row click. Operators must make an additional affirmative input after requesting commitment. This adds interaction effort and may reduce throughput compared with immediate mutation. The supplied documentation does not establish the size of that time cost.

**Alternative rejected:** I rejected immediate mutation followed by Undo as a substitute for confirmation. Undo could support reversibility, but it would act after the change and would not satisfy QA’s request to confirm first. Compliance’s R-04 requirements for named attribution, timestamps, and reversibility remain separate obligations; a confirmation modal alone does not satisfy them.

---



### Alignment with the UX Interaction Count

The current `UX_RATIONALE.md` interaction table lists disposition, reason, commit, and next-case navigation as four interactions. Its keymap also mentions a confirmation modal, but the table does not count accepting that modal.

For the chosen design, the intended decision sequence after case selection is:


| Interaction | Action                                  |
| ----------- | --------------------------------------- |
| **1**       | Select the disposition.                 |
| **2**       | Select the reason code.                 |
| **3**       | Open the confirmation.                  |
| **4**       | Explicitly confirm the proposed change. |


**Intended decision count:** $1 + 1 + 1 + 1 = 4$ interactions after selection. This fits assessment R2 only if each step actually takes one input. Any additional focus movement, dropdown navigation, or confirmation input must be counted in the live walkthrough.

Manual next-case navigation is a further input, making five inputs for a decision followed by advancement. The current UX document also describes automatic advancement in its time budget, so its actual navigation behaviour and interaction table need to be reconciled. This decision record does not certify the live interaction count or automatic advancement.