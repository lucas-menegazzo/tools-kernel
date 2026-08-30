-- Customer Refund Requests (Atendimento) Database Schema
-- Generated from apps/customer-refund-requests/app.yaml (issue #8)

CREATE SCHEMA IF NOT EXISTS customer_refunds;

CREATE TABLE customer_refunds.refund_requests (
    id BIGSERIAL PRIMARY KEY,
    request_id TEXT NOT NULL UNIQUE,
    customer_name TEXT NOT NULL,
    customer_cpf TEXT NOT NULL,
    customer_email TEXT NOT NULL,
    amount NUMERIC(19,2) NOT NULL CHECK (amount > 0),
    reason TEXT NOT NULL,
    requested_at TIMESTAMP WITH TIME ZONE NOT NULL,
    resolution_deadline TIMESTAMP WITH TIME ZONE NOT NULL,
    status TEXT NOT NULL DEFAULT 'Registrada' CHECK (status IN ('Registrada', 'Aguardando aprovacao', 'Aprovada', 'Recusada', 'Concluida')),
    team TEXT NOT NULL,
    created_by TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Indexes for RLS and queue performance
CREATE INDEX idx_refund_requests_status ON customer_refunds.refund_requests(status);
CREATE INDEX idx_refund_requests_team ON customer_refunds.refund_requests(team);
CREATE INDEX idx_refund_requests_created_by ON customer_refunds.refund_requests(created_by);
CREATE INDEX idx_refund_requests_amount ON customer_refunds.refund_requests(amount);
CREATE INDEX idx_refund_requests_resolution_deadline ON customer_refunds.refund_requests(resolution_deadline);

-- Archive instead of delete: soft-delete columns and hard-delete protection.
-- The request states "nada pode ser apagado de verdade, so arquivado" without a
-- period, so the repository's operational retention policy is the declared basis.
SELECT create_soft_delete_table('customer_refunds.refund_requests', 10, 'operational-data-retention-policy');
SELECT attach_soft_delete_protection('customer_refunds.refund_requests');

-- Enable Row Level Security
ALTER TABLE customer_refunds.refund_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_refunds.refund_requests FORCE ROW LEVEL SECURITY;

-- RLS: analysts and supervisors see only their own team's requests.
-- The manager sees every team, because refunds above R$ 5,000 are approved by
-- the manager regardless of which team registered them.
CREATE POLICY refund_requests_select ON customer_refunds.refund_requests
    FOR SELECT
    TO tools_kernel_app
    USING (
        ((has_role('Analista Atendimento') OR has_role('Supervisor Atendimento'))
         AND team = current_actor_team())
        OR has_role('Gerente Atendimento')
    );

CREATE POLICY refund_requests_insert ON customer_refunds.refund_requests
    FOR INSERT
    TO tools_kernel_app
    WITH CHECK (
        ((has_role('Analista Atendimento') OR has_role('Supervisor Atendimento'))
         AND team = current_actor_team())
        OR has_role('Gerente Atendimento')
    );

CREATE POLICY refund_requests_update ON customer_refunds.refund_requests
    FOR UPDATE
    TO tools_kernel_app
    USING (
        ((has_role('Analista Atendimento') OR has_role('Supervisor Atendimento'))
         AND team = current_actor_team())
        OR has_role('Gerente Atendimento')
    )
    WITH CHECK (
        ((has_role('Analista Atendimento') OR has_role('Supervisor Atendimento'))
         AND team = current_actor_team())
        OR has_role('Gerente Atendimento')
    );

-- Single gate for revealing the customer CPF: Atendimento supervisors and
-- managers, plus the kernel roles that may already reveal PII.
CREATE FUNCTION customer_refunds.can_reveal_customer_cpf()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN can_reveal_pii()
        OR has_role('Supervisor Atendimento')
        OR has_role('Gerente Atendimento');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Queue view: the CPF leaves the data layer masked unless the gate opens it.
CREATE VIEW customer_refunds.refund_request_queue
WITH (security_invoker = on)
AS
SELECT
    r.id,
    r.request_id,
    r.customer_name,
    mask_cpf(r.customer_cpf, customer_refunds.can_reveal_customer_cpf()) AS customer_cpf,
    r.customer_email,
    r.amount,
    r.reason,
    r.requested_at,
    r.resolution_deadline,
    r.status,
    r.team,
    r.created_by,
    r.created_at,
    r.updated_at
FROM customer_refunds.refund_requests r
WHERE r.deleted_at IS NULL;

-- Amount bands: alcadas exactly as the request states them
INSERT INTO amount_approval_bands (table_name, min_amount, max_amount, approving_roles, required_approvals, description)
VALUES
    ('customer_refunds.refund_requests', 0, 500, ARRAY['Analista Atendimento', 'Supervisor Atendimento', 'Gerente Atendimento'], 1, 'Reembolso ate R$ 500 o analista aprova sozinho'),
    ('customer_refunds.refund_requests', 500, 5000, ARRAY['Supervisor Atendimento', 'Gerente Atendimento'], 1, 'Acima de R$ 500 precisa de aprovacao do supervisor'),
    ('customer_refunds.refund_requests', 5000, NULL, ARRAY['Gerente Atendimento'], 1, 'Acima de R$ 5.000 precisa do gerente')
ON CONFLICT (table_name, min_amount, COALESCE(max_amount, 'Infinity'::NUMERIC)) DO NOTHING;

-- 15 calendar days from the request date, per the internal Atendimento SLA
CREATE FUNCTION customer_refunds.check_resolution_deadline()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.resolution_deadline > NEW.requested_at + INTERVAL '15 days' THEN
        RAISE EXCEPTION 'Resolution deadline for % cannot exceed 15 calendar days from the request date', NEW.request_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- A request only reaches 'Aprovada' with the approvals its amount band requires.
-- The band, the required count and the proposer rule live in the kernel; this
-- trigger only asks the kernel whether they are satisfied.
CREATE FUNCTION customer_refunds.check_refund_request_approval()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'Aprovada' AND OLD.status <> 'Aprovada' THEN
        IF NOT has_sufficient_amount_approvals('customer_refunds.refund_requests', NEW.id::TEXT) THEN
            RAISE EXCEPTION 'Refund request % cannot be approved without the approvals required for R$ %', NEW.request_id, NEW.amount;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION customer_refunds.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Audit, deadline and approval triggers are attached in seed-data.sql, after the
-- seed rows are loaded, so the trail starts with real operator activity.

-- Grant permissions to application role
GRANT USAGE ON SCHEMA customer_refunds TO tools_kernel_app;
GRANT SELECT, INSERT, UPDATE ON customer_refunds.refund_requests TO tools_kernel_app;
GRANT SELECT ON customer_refunds.refund_request_queue TO tools_kernel_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA customer_refunds TO tools_kernel_app;
GRANT EXECUTE ON FUNCTION customer_refunds.can_reveal_customer_cpf() TO tools_kernel_app;
GRANT EXECUTE ON FUNCTION customer_refunds.check_resolution_deadline() TO tools_kernel_app;
GRANT EXECUTE ON FUNCTION customer_refunds.check_refund_request_approval() TO tools_kernel_app;
GRANT EXECUTE ON FUNCTION customer_refunds.update_updated_at() TO tools_kernel_app;
