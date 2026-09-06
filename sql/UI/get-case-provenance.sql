SELECT
    note_id,
    audit_id,
    -- Why this case entered the queue
    triage_rule,
    provenance_rule_fired,
    -- Audit provenance
    rubric_version,
    composite_score,
    pass_threshold,
    score_gap,
    -- SLA provenance
    sla_config_id,
    target_minutes,
    sla_status,
    delivery_minutes,
    -- Context
    product_line,
    priority,
    chicago_business_date,
    submitted_at_utc,
    delivered_at_utc
FROM triage_queue_view
WHERE note_id = {{ triageTable.selectedRow.note_id }};