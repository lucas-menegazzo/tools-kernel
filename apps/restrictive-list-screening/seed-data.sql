-- Restrictive List Screening Seed Data
-- 1,500 alerts with 1-6 matches each, realistic similarity scores

-- Temporarily drop any already-attached triggers to avoid seed audit noise
DROP TRIGGER IF EXISTS audit_trigger ON screening.alerts;
DROP TRIGGER IF EXISTS audit_trigger ON screening.list_matches;
DROP TRIGGER IF EXISTS update_screening_alerts_updated_at ON screening.alerts;
DROP TRIGGER IF EXISTS update_screening_list_matches_updated_at ON screening.list_matches;
DROP TRIGGER IF EXISTS enforce_alert_closure ON screening.alerts;

-- Insert 1,500 alerts
WITH alerts_data AS (
    INSERT INTO screening.alerts (
        alert_id, tax_id, customer_name, screened_at, status,
        assigned_to, team, analysis_deadline, created_by
    )
    SELECT
        'SCR-' || LPAD(i::text, 8, '0') || '-2026',
        generate_invalid_cpf(),
        generate_brazilian_name(),
        NOW() - (random() * INTERVAL '90 days'),
        'Aberto',
        analysts[(i % 4) + 1],
        CASE WHEN i % 2 = 0 THEN 'Team A' ELSE 'Team B' END,
        NOW() - (random() * INTERVAL '90 days') + INTERVAL '2 days',
        analysts[(i % 4) + 1]
    FROM generate_series(1, 1500) AS i,
    LATERAL (
        SELECT ARRAY[
            'marina.alves@thefintechcompany.com.br',
            'rafael.souza@thefintechcompany.com.br',
            'beatriz.lima@thefintechcompany.com.br',
            'tiago.rocha@thefintechcompany.com.br'
        ] AS analysts
    ) a
    RETURNING alert_id
),
match_counts AS (
    SELECT alert_id, (floor(random() * 6) + 1)::int AS n
    FROM alerts_data
),
match_rows AS (
    SELECT
        a.alert_id,
        a.alert_id || '-M' || j AS match_id,
        lists[(floor(random() * 3) + 1)::int] AS list_name,
        generate_brazilian_name() AS matched_name,
        CASE
            WHEN random() < 0.73 THEN (random() * 0.3)::numeric(5,4)
            WHEN random() < 0.98 THEN (0.3 + random() * 0.5)::numeric(5,4)
            ELSE (0.8 + random() * 0.2)::numeric(5,4)
        END AS similarity_score
    FROM match_counts a
    CROSS JOIN LATERAL generate_series(1, a.n) AS j
    CROSS JOIN (SELECT ARRAY['CSNU', 'OFAC', 'PEP'] AS lists) l
)
INSERT INTO screening.list_matches (
    match_id, alert_id, list_name, matched_name, similarity_score,
    decision, justification, created_by
)
SELECT
    match_id,
    alert_id,
    list_name,
    matched_name,
    similarity_score,
    CASE
        WHEN similarity_score < 0.3 THEN 'falso_positivo'
        WHEN similarity_score >= 0.8 THEN 'match_confirmado'
        ELSE 'indeterminado'
    END,
    CASE
        WHEN similarity_score < 0.3 THEN 'Similaridade baixa; falso positivo automatico'
        WHEN similarity_score >= 0.8 THEN 'Similaridade alta; match confirmado - aguarda aprovacao'
        ELSE 'Aguardando analise do analista'
    END,
    'system.seed'
FROM match_rows;

-- Approve all high-similarity (match_confirmado) matches using a supervisor actor
DO $$
DECLARE
    m screening.list_matches%ROWTYPE;
    v_supervisor_email TEXT := 'helena.castro@thefintechcompany.com.br';
    v_supervisor_role TEXT := 'Supervisor Compliance';
BEGIN
    PERFORM set_actor_context(v_supervisor_email, ARRAY[v_supervisor_role], 'Team A');
    FOR m IN
        SELECT * FROM screening.list_matches
        WHERE decision = 'match_confirmado'
          AND deleted_at IS NULL
    LOOP
        INSERT INTO approvals (
            target_table, target_record_id, actor_id, actor_role, decision, reason
        ) VALUES (
            'screening.list_matches',
            m.match_id,
            v_supervisor_email,
            v_supervisor_role,
            'approved',
            'Triagem seed: aprovacao de match confirmado'
        );
    END LOOP;
END $$;

-- Re-enable triggers for normal operations
SELECT attach_audit_trigger('screening.alerts');
SELECT attach_audit_trigger('screening.list_matches');

CREATE TRIGGER update_screening_alerts_updated_at
    BEFORE UPDATE ON screening.alerts
    FOR EACH ROW EXECUTE FUNCTION screening.update_updated_at();

CREATE TRIGGER update_screening_list_matches_updated_at
    BEFORE UPDATE ON screening.list_matches
    FOR EACH ROW EXECUTE FUNCTION screening.update_updated_at();

CREATE TRIGGER enforce_alert_closure
    BEFORE UPDATE OF status ON screening.alerts
    FOR EACH ROW EXECUTE FUNCTION screening.check_alert_closure();
