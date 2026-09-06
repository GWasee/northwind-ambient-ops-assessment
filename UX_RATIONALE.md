# UX_RATIONALE.md

## Northwind Ambient Ops BI Technical Assessment
### Part 2: Triage Workbench UX Rationale

---

## 1. Operator Goal

The Triage Workbench supports the Audit Triage Lead in reviewing failed audit cases, understanding why a case entered the queue, and taking an operational decision.

The implemented design prioritizes the operator workflow with a single-screen Retool application containing:
- KPI summary
- Failed audit queue
- Case provenance panel

---

## 2. Implemented Layout Decision

The completed layout uses two primary columns:

```
-------------------------------------------------
| Triage Workbench              KPI Summary      |
-------------------------------------------------
| Failed Audit Queue      | Case Provenance      |
| Table1                  | Container1           |
-------------------------------------------------
```

### Left Column: Failed Audit Queue

**Completed:**
- Displays failed audit cases requiring action.
- Provides case selection.
- Shows operational context.

**Displayed fields:**
- Note ID
- Product
- Priority
- MDS
- Clinician
- Status

### Right Column: Case Provenance

**Completed:** The provenance panel explains why a selected case entered the queue.

**Displayed:**
- Queue rule fired
- Composite score
- Required threshold
- Rubric version
- Effective SLA target
- Product line
- Priority
- Note date
- Dimension scores

---

## R1: Screen Size

**Status: Completed**

The primary working pane is designed for a 1366×768 viewport.

The layout keeps the KPI area and working pane visible without requiring page-level vertical scrolling.

---

## R2: Interaction Count

**Status: Pending**

Planned workflow:

1. Navigate/select case
2. Set disposition
3. Set reason code
4. Commit decision

Final timing and interaction validation will be added after keyboard workflow completion.

---

## R3: Keyboard Workflow

**Status: Pending**

Planned keymap:

| Key | Action |
|---|---|
| ↑ / ↓ | Navigate cases |
| A | Approve |
| R | Reject |
| E | Escalate |
| N | Needs Review |
| Ctrl + Enter | Commit |

---

## R4: Large Queue Handling

**Status: Pending**

Will document:
- 3,000-row queue support
- Filter persistence
- Selection persistence
- Refresh behaviour

---

## R5: Provenance Panel

**Status: Completed**

The panel provides:

| Requirement | Implementation |
|---|---|
| Rule fired | Queue rule |
| Threshold | Required audit threshold |
| Rubric version | Active rubric version |
| SLA target | Effective SLA target on note date |

---

## R6: Application States

**Status: Pending**

Will implement and document:
- Empty queue
- Loading
- Upstream error

---

## R7: Commit Behaviour

**Status: Partially Completed**

SQL support exists for:
- Explicit commit action
- State updates
- Event logging

Remaining:
- Optimistic UI update
- Rollback demonstration

---

## R8: Bulk Action

**Status: Pending**

Will add:
- Multi-row selection
- Confirmation modal
- Exact affected row count
- Safe repeated submission

---

## R9: Accessibility

**Status: Partially Completed**

Status values include text labels.

Remaining:
- Greyscale validation
- Contrast validation

---

## R10: Correct Queue Logic

**Status: Completed**

The queue is generated from corrected Part 1 logic rather than the original provided queries.

---

## 13. Rejected Layouts

**Status: Pending**

**Layout 1:**

Reason:

**Layout 2:**

Reason:

---

## 14. Deliberate Trade-off

**Status: Pending**

Requirement not fully satisfied:

Trade-off:

---

## 15. Annotated Screenshot

**Status: Pending**

Will be added after completing remaining interaction requirements.
