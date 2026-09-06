SELECT
    COUNT(*) AS total_cases,
    COUNT(*) FILTER (WHERE sla_status = 'BREACHED') AS breached_cases,
    COUNT(*) FILTER (WHERE triage_rule = 'CONFIRMED_AUDIT_FAIL') AS failed_cases
FROM triage_queue_view;
