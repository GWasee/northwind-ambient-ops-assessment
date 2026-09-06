-- =====================================================================
-- Retool Query: get_case_details.sql
-- Purpose: Selected case information and raw 7 audit sub-scores
-- Retool Component: Case Details & Audit Inspection Panel
-- Binding: get_case_details.data
-- Parameter: table1.selectedRow.note_id
-- =====================================================================

SELECT
    q.*,
    na.score_accuracy,
    na.score_completeness,
    na.score_formatting,
    na.score_terminology,
    na.score_hpi,
    na.score_ros,
    na.score_plan,
    na.rubric_version

FROM note q

JOIN note_audit na
  ON q.note_id = na.note_id

WHERE q.note_id = {{table1.selectedRow.note_id}};
