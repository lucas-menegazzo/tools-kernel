-- Credit Card Dispute Review Queue Database Schema
-- Generated from apps/dispute-review-queue/app.yaml

-- Create disputes schema
CREATE SCHEMA IF NOT EXISTS disputes;

-- Main disputes table
CREATE TABLE disputes.disputes (
    id BIGSERIAL PRIMARY KEY,
    dispute_id TEXT NOT NULL UNIQUE,
    cpf TEXT NOT NULL,
    amount NUMERIC(19,4) NOT NULL CHECK (amount > 0),
    reason TEXT NOT NULL,
    response_deadline TIMESTAMP WITH TIME ZONE NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('Aberto', 'Em analise', 'Aguardando aprovacao', 'Aprovado', 'Rejeitado', 'Concluido')),
    assigned_analyst TEXT NOT NULL,
    created_by TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    -- Soft delete columns
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by TEXT,
    retention_period INTEGER DEFAULT 10,
    retention_basis TEXT DEFAULT 'operational-data-retention-policy'
);

-- Create indexes for performance
CREATE INDEX idx_disputes_status ON disputes.disputes(status) WHERE deleted_at IS NULL;
CREATE INDEX idx_disputes_assigned_analyst ON disputes.disputes(assigned_analyst) WHERE deleted_at IS NULL;
CREATE INDEX idx_disputes_response_deadline ON disputes.disputes(response_deadline) WHERE deleted_at IS NULL;
CREATE INDEX idx_disputes_amount ON disputes.disputes(amount) WHERE deleted_at IS NULL;
CREATE INDEX idx_disputes_active ON disputes.disputes(created_at DESC) WHERE deleted_at IS NULL;

-- Attach soft delete protection
SELECT create_soft_delete_table('disputes.disputes', 10, 'operational-data-retention-policy');
SELECT attach_soft_delete_protection('disputes.disputes');

-- Enable Row Level Security
ALTER TABLE disputes.disputes ENABLE ROW LEVEL SECURITY;
ALTER TABLE disputes.disputes FORCE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY disputes_select ON disputes.disputes
    FOR SELECT
    TO tools_kernel_app
    USING (
        (assigned_analyst = current_actor_id() OR has_role('Supervisor Contestacoes') OR has_role('Gerente Contestacoes'))
        AND (has_role('Analista Contestacoes') OR has_role('Supervisor Contestacoes') OR has_role('Gerente Contestacoes'))
    );

CREATE POLICY disputes_insert ON disputes.disputes
    FOR INSERT
    TO tools_kernel_app
    WITH CHECK (
        has_role('Analista Contestacoes')
        OR has_role('Supervisor Contestacoes')
        OR has_role('Gerente Contestacoes')
    );

CREATE POLICY disputes_update ON disputes.disputes
    FOR UPDATE
    TO tools_kernel_app
    USING (
        assigned_analyst = current_actor_id()
        OR has_role('Supervisor Contestacoes')
        OR has_role('Gerente Contestacoes')
    )
    WITH CHECK (
        assigned_analyst = current_actor_id()
        OR has_role('Supervisor Contestacoes')
        OR has_role('Gerente Contestacoes')
    );

-- Updated_at trigger function
CREATE OR REPLACE FUNCTION disputes.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Approval check: high-value disputes require enough approvals before approval.
-- The helper looks at the amount_approval_bands entry for this table, avoiding
-- the schema-qualified name limitation of the generic kernel helper.
CREATE OR REPLACE FUNCTION disputes.check_dispute_approval()
RETURNS TRIGGER AS $$
DECLARE
    v_approving_roles TEXT[];
    v_required INTEGER;
    v_approved INTEGER;
BEGIN
    IF NEW.status = 'Aprovado' THEN
        SELECT approving_roles, required_approvals
        INTO v_approving_roles, v_required
        FROM amount_approval_bands
        WHERE table_name = 'disputes.disputes'
          AND NEW.amount >= min_amount
          AND (max_amount IS NULL OR NEW.amount < max_amount)
        ORDER BY min_amount DESC
        LIMIT 1;

        IF v_required IS NOT NULL THEN
            SELECT COUNT(DISTINCT actor_id)
            INTO v_approved
            FROM approvals
            WHERE target_table = 'disputes.disputes'
              AND target_record_id = NEW.id::text
              AND decision = 'approved'
              AND actor_role = ANY(v_approving_roles);

            IF v_approved < v_required THEN
                RAISE EXCEPTION 'Dispute % cannot be approved: amount above threshold requires % distinct approvals from %', NEW.dispute_id, v_required, v_approving_roles;
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Configure amount-based approval band for high-value disputes
INSERT INTO amount_approval_bands (table_name, min_amount, max_amount, approving_roles, required_approvals, description)
VALUES (
    'disputes.disputes',
    10000,
    NULL,
    ARRAY['Supervisor Contestacoes', 'Gerente Contestacoes'],
    2,
    'Disputes above R$ 10,000 require two distinct supervisor/manager approvals'
) ON CONFLICT (table_name, min_amount, COALESCE(max_amount, 'Infinity'::NUMERIC)) DO NOTHING;

-- Attach audit and update triggers
SELECT attach_audit_trigger('disputes.disputes');

CREATE TRIGGER update_disputes_updated_at
    BEFORE UPDATE ON disputes.disputes
    FOR EACH ROW EXECUTE FUNCTION disputes.update_updated_at();

CREATE TRIGGER enforce_dispute_approval
    BEFORE UPDATE OF status ON disputes.disputes
    FOR EACH ROW EXECUTE FUNCTION disputes.check_dispute_approval();

-- Grant permissions to application role
GRANT USAGE ON SCHEMA disputes TO tools_kernel_app;
GRANT SELECT, INSERT, UPDATE ON disputes.disputes TO tools_kernel_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA disputes TO tools_kernel_app;
GRANT EXECUTE ON FUNCTION disputes.update_updated_at() TO tools_kernel_app;
GRANT EXECUTE ON FUNCTION disputes.check_dispute_approval() TO tools_kernel_app;
