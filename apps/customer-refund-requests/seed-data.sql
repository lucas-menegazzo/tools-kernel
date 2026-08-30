-- Customer Refund Requests Seed Data
-- 900 synthetic requests across two Atendimento teams.
-- CPFs are deliberately invalid (generate_invalid_cpf) and names are synthetic.

CREATE TABLE IF NOT EXISTS users (
    email TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    role TEXT NOT NULL,
    team TEXT
);

INSERT INTO users (email, name, role, team) VALUES
-- Analysts
('luana.ferreira@thefintechcompany.com.br', 'Luana Ferreira', 'Analista Atendimento', 'Atendimento A'),
('paulo.barreto@thefintechcompany.com.br', 'Paulo Barreto', 'Analista Atendimento', 'Atendimento A'),
('renata.moraes@thefintechcompany.com.br', 'Renata Moraes', 'Analista Atendimento', 'Atendimento B'),
('sergio.batista@thefintechcompany.com.br', 'Sergio Batista', 'Analista Atendimento', 'Atendimento B'),
-- Supervisors
('carolina.duarte@thefintechcompany.com.br', 'Carolina Duarte', 'Supervisor Atendimento', 'Atendimento A'),
('marcelo.viana@thefintechcompany.com.br', 'Marcelo Viana', 'Supervisor Atendimento', 'Atendimento B'),
-- Manager
('patricia.rezende@thefintechcompany.com.br', 'Patricia Rezende', 'Gerente Atendimento', 'Management')
ON CONFLICT (email) DO NOTHING;

-- Keep the seed load out of the audit trail and out of the deadline/approval
-- triggers; both are attached at the end of this file.
DROP TRIGGER IF EXISTS audit_trigger ON customer_refunds.refund_requests;
DROP TRIGGER IF EXISTS enforce_resolution_deadline ON customer_refunds.refund_requests;
DROP TRIGGER IF EXISTS enforce_refund_request_approval ON customer_refunds.refund_requests;
DROP TRIGGER IF EXISTS update_refund_requests_updated_at ON customer_refunds.refund_requests;

-- One independent draw per row, so amount band, status, team and reason stay
-- uncorrelated in the generated queue.
WITH draws AS (
    SELECT
        i,
        NOW() - (random() * INTERVAL '60 days') AS requested_at,
        random() AS amount_band,
        random() AS status_draw,
        (floor(random() * 5) + 1)::int AS reason_index,
        (floor(random() * 4) + 1)::int AS analyst_index
    FROM generate_series(1, 900) AS i
)
INSERT INTO customer_refunds.refund_requests (
    request_id, customer_name, customer_cpf, customer_email, amount, reason,
    requested_at, resolution_deadline, status, team, created_by
)
SELECT
    'REB-' || LPAD(draw.i::text, 6, '0') || '-2026',
    generate_brazilian_name(),
    generate_invalid_cpf(),
    'cliente' || draw.i || '@exemplo.com.br',
    CASE
        WHEN draw.amount_band < 0.6 THEN (20 + random() * 480)::numeric(19,2)
        WHEN draw.amount_band < 0.9 THEN (500 + random() * 4500)::numeric(19,2)
        ELSE (5000 + random() * 20000)::numeric(19,2)
    END,
    reasons[draw.reason_index],
    draw.requested_at,
    draw.requested_at + INTERVAL '15 days',
    CASE
        WHEN draw.status_draw < 0.2 THEN 'Registrada'
        WHEN draw.status_draw < 0.4 THEN 'Aguardando aprovacao'
        WHEN draw.status_draw < 0.6 THEN 'Recusada'
        ELSE 'Concluida'
    END,
    analyst_teams[draw.analyst_index],
    analyst_emails[draw.analyst_index]
FROM draws draw
CROSS JOIN (
    SELECT ARRAY[
        'Cobranca duplicada no cartao',
        'Produto nao entregue pelo parceiro',
        'Cliente cancelou a assinatura no prazo',
        'Valor cobrado diferente do contratado',
        'Transacao nao reconhecida pelo cliente'
    ] AS reasons
) r
CROSS JOIN (
    -- Each analyst registers requests for their own team only
    SELECT
        ARRAY[
            'luana.ferreira@thefintechcompany.com.br',
            'paulo.barreto@thefintechcompany.com.br',
            'renata.moraes@thefintechcompany.com.br',
            'sergio.batista@thefintechcompany.com.br'
        ] AS analyst_emails,
        ARRAY[
            'Atendimento A',
            'Atendimento A',
            'Atendimento B',
            'Atendimento B'
        ] AS analyst_teams
) a;

-- A handful of already-approved requests, each with the approval record its
-- band requires and an approver who is not the requester.
WITH to_approve AS (
    SELECT
        r.id,
        r.created_by,
        CASE
            WHEN r.amount >= 5000 THEN 'Gerente Atendimento'
            WHEN r.amount >= 500 THEN 'Supervisor Atendimento'
            ELSE 'Analista Atendimento'
        END AS approver_role,
        CASE
            WHEN r.amount >= 5000 THEN 'patricia.rezende@thefintechcompany.com.br'
            WHEN r.amount >= 500 AND r.team = 'Atendimento A' THEN 'carolina.duarte@thefintechcompany.com.br'
            WHEN r.amount >= 500 THEN 'marcelo.viana@thefintechcompany.com.br'
            WHEN r.team = 'Atendimento A' THEN 'paulo.barreto@thefintechcompany.com.br'
            ELSE 'sergio.batista@thefintechcompany.com.br'
        END AS approver_email
    FROM customer_refunds.refund_requests r
    WHERE r.status = 'Aguardando aprovacao'
    ORDER BY r.id
    LIMIT 60
),
recorded AS (
    INSERT INTO approvals (target_table, target_record_id, actor_id, actor_role, decision, reason)
    SELECT
        'customer_refunds.refund_requests',
        t.id::text,
        t.approver_email,
        t.approver_role,
        'approved',
        'Aprovado conforme alcada'
    FROM to_approve t
    -- Quem pediu nao aprova: skip the rows where the only approver in the band
    -- would be the requester
    WHERE t.created_by <> t.approver_email
    ON CONFLICT (target_table, target_record_id, actor_id) DO NOTHING
    RETURNING target_record_id
)
UPDATE customer_refunds.refund_requests
SET status = 'Aprovada'
WHERE id::text IN (SELECT target_record_id FROM recorded);

-- A few archived requests: archived, never deleted.
UPDATE customer_refunds.refund_requests
SET deleted_at = NOW() - INTERVAL '5 days',
    deleted_by = 'carolina.duarte@thefintechcompany.com.br'
WHERE id IN (
    SELECT id FROM customer_refunds.refund_requests
    WHERE status = 'Concluida'
    ORDER BY id DESC
    LIMIT 12
);

-- Attach the triggers now that the seed rows are in place
SELECT attach_audit_trigger('customer_refunds.refund_requests');

CREATE TRIGGER enforce_resolution_deadline
    BEFORE INSERT OR UPDATE ON customer_refunds.refund_requests
    FOR EACH ROW EXECUTE FUNCTION customer_refunds.check_resolution_deadline();

CREATE TRIGGER enforce_refund_request_approval
    BEFORE UPDATE OF status ON customer_refunds.refund_requests
    FOR EACH ROW EXECUTE FUNCTION customer_refunds.check_refund_request_approval();

CREATE TRIGGER update_refund_requests_updated_at
    BEFORE UPDATE ON customer_refunds.refund_requests
    FOR EACH ROW EXECUTE FUNCTION customer_refunds.update_updated_at();

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA customer_refunds TO tools_kernel_app;
