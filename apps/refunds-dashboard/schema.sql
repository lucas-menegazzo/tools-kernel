-- Refunds Dashboard app schema
-- Derived from legacy/RefundsDashboard/ and legacy/dataverse/cr8a2_devolucao.table.json

CREATE SCHEMA IF NOT EXISTS refunds;

-- Refund table (Devolucao)
CREATE TABLE refunds.devolucoes (
    id BIGSERIAL PRIMARY KEY,
    case_number TEXT NOT NULL UNIQUE,
    cpf_cliente TEXT NOT NULL,
    nome_cliente TEXT NOT NULL,
    valor NUMERIC(19,2) NOT NULL CHECK (valor > 0),
    motivo TEXT NOT NULL CHECK (motivo IN ('Cobranca indevida', 'Produto nao entregue', 'Fraude confirmada', 'Duplicidade', 'Outro')),
    status TEXT NOT NULL DEFAULT 'Solicitada' CHECK (status IN ('Solicitada', 'Aguardando aprovacao', 'Aprovada', 'Recusada', 'Concluida')),
    solicitado_por TEXT NOT NULL,
    solicitada_em TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    team TEXT NOT NULL,
    created_by TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Indexes for RLS and queue performance
CREATE INDEX idx_devolucoes_status ON refunds.devolucoes(status);
CREATE INDEX idx_devolucoes_solicitado_por ON refunds.devolucoes(solicitado_por);
CREATE INDEX idx_devolucoes_team ON refunds.devolucoes(team);
CREATE INDEX idx_devolucoes_valor ON refunds.devolucoes(valor);

-- Add soft delete columns and protection
SELECT create_soft_delete_table('refunds.devolucoes');

-- Enable Row Level Security
ALTER TABLE refunds.devolucoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE refunds.devolucoes FORCE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY devolucoes_select ON refunds.devolucoes
    FOR SELECT
    TO tools_kernel_app
    USING (
        (has_role('Analista Senior') AND team = current_actor_team())
        OR (has_role('Supervisor Operacoes') AND team = current_actor_team())
        OR has_role('Gerente Operacoes')
    );

CREATE POLICY devolucoes_insert ON refunds.devolucoes
    FOR INSERT
    TO tools_kernel_app
    WITH CHECK (
        has_role('Analista Senior')
        OR has_role('Supervisor Operacoes')
        OR has_role('Gerente Operacoes')
    );

CREATE POLICY devolucoes_update ON refunds.devolucoes
    FOR UPDATE
    TO tools_kernel_app
    USING (
        (has_role('Analista Senior') AND team = current_actor_team())
        OR (has_role('Supervisor Operacoes') AND team = current_actor_team())
        OR has_role('Gerente Operacoes')
    );

-- Amount-based approval bands (reconciled from legacy: lower ceiling 50,000)
INSERT INTO amount_approval_bands (table_name, min_amount, max_amount, approving_roles, required_approvals, description)
VALUES
    ('refunds.devolucoes', 0, 5000, ARRAY['Analista Senior', 'Supervisor Operacoes', 'Gerente Operacoes'], 1, 'Refunds up to R$ 5,000 require one senior analyst approval'),
    ('refunds.devolucoes', 5000, 50000, ARRAY['Supervisor Operacoes', 'Gerente Operacoes'], 1, 'Refunds from R$ 5,000 to R$ 50,000 require one operations supervisor approval'),
    ('refunds.devolucoes', 50000, NULL, ARRAY['Gerente Operacoes'], 2, 'Refunds above R$ 50,000 require two distinct operations manager approvals');

-- Function to approve one or many refunds (single and bulk share this code path)
CREATE FUNCTION refunds.aprovar_devolucoes(p_devolucao_ids BIGINT[], p_decision TEXT, p_reason TEXT DEFAULT NULL)
RETURNS TABLE(devolucao_id BIGINT, success BOOLEAN, message TEXT) AS $$
DECLARE
    v_id BIGINT;
    v_amount NUMERIC;
    v_proposer TEXT;
    v_band amount_approval_bands;
    v_actor_id TEXT;
    v_actor_roles TEXT[];
    v_actor_role TEXT;
    v_approved_count INTEGER;
    v_required INTEGER;
    v_status TEXT;
BEGIN
    v_actor_id := current_actor_id();
    v_actor_roles := current_actor_roles();

    FOREACH v_id IN ARRAY p_devolucao_ids
    LOOP
        BEGIN
            -- Get refund value and proposer
            SELECT valor, solicitado_por INTO v_amount, v_proposer
            FROM refunds.devolucoes
            WHERE id = v_id;

            IF v_amount IS NULL THEN
                devolucao_id := v_id;
                success := false;
                message := 'Refund not found';
                RETURN NEXT;
                CONTINUE;
            END IF;

            -- Segregation of duties: proposer cannot approve
            IF v_proposer = v_actor_id THEN
                devolucao_id := v_id;
                success := false;
                message := 'Proposer cannot approve their own refund';
                RETURN NEXT;
                CONTINUE;
            END IF;

            -- Get band for this amount
            SELECT * INTO v_band FROM get_amount_approval_band('refunds.devolucoes', v_amount);

            IF v_band IS NULL THEN
                devolucao_id := v_id;
                success := false;
                message := 'No approval band configured for this amount';
                RETURN NEXT;
                CONTINUE;
            END IF;

            -- Check role
            IF NOT (v_band.approving_roles && v_actor_roles) THEN
                devolucao_id := v_id;
                success := false;
                message := 'Actor does not have required role for this amount';
                RETURN NEXT;
                CONTINUE;
            END IF;

            v_actor_role := (SELECT unnest FROM unnest(v_actor_roles) unnest WHERE unnest = ANY(v_band.approving_roles) LIMIT 1);

            -- Check already approved by this actor
            IF EXISTS (
                SELECT 1 FROM approvals
                WHERE target_table = 'refunds.devolucoes'
                  AND target_record_id = v_id::TEXT
                  AND actor_id = v_actor_id
            ) THEN
                devolucao_id := v_id;
                success := false;
                message := 'Actor already recorded a decision for this refund';
                RETURN NEXT;
                CONTINUE;
            END IF;

            -- Record the approval decision
            INSERT INTO approvals (target_table, target_record_id, actor_id, actor_role, decision, reason)
            VALUES ('refunds.devolucoes', v_id::TEXT, v_actor_id, v_actor_role, p_decision, p_reason);

            -- If approved and we now have enough distinct approvals, mark as Aprovada
            IF p_decision = 'approved' THEN
                SELECT COUNT(DISTINCT actor_id) INTO v_approved_count
                FROM approvals
                WHERE target_table = 'refunds.devolucoes'
                  AND target_record_id = v_id::TEXT
                  AND decision = 'approved';

                IF v_approved_count >= v_band.required_approvals THEN
                UPDATE refunds.devolucoes
                SET status = 'Aprovada', updated_at = NOW()
                WHERE id = v_id;
            ELSE
                UPDATE refunds.devolucoes
                SET status = 'Aguardando aprovacao', updated_at = NOW()
                WHERE id = v_id AND status = 'Solicitada';
            END IF;
            ELSIF p_decision = 'refused' THEN
                UPDATE refunds.devolucoes
                SET status = 'Recusada', updated_at = NOW()
                WHERE id = v_id;
            END IF;

            devolucao_id := v_id;
            success := true;
            message := 'Decision recorded successfully';
            RETURN NEXT;

        EXCEPTION WHEN OTHERS THEN
            devolucao_id := v_id;
            success := false;
            message := SQLERRM;
            RETURN NEXT;
        END;
    END LOOP;

    RETURN;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger function to update updated_at
CREATE FUNCTION refunds.update_devolucoes_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers
CREATE TRIGGER update_devolucoes_updated_at
    BEFORE UPDATE ON refunds.devolucoes
    FOR EACH ROW EXECUTE FUNCTION refunds.update_devolucoes_updated_at();

SELECT attach_audit_trigger('refunds.devolucoes');
SELECT attach_soft_delete_protection('refunds.devolucoes');

-- Grant permissions to application role
GRANT USAGE ON SCHEMA refunds TO tools_kernel_app;
GRANT SELECT, INSERT, UPDATE ON refunds.devolucoes TO tools_kernel_app;
GRANT EXECUTE ON FUNCTION refunds.aprovar_devolucoes(BIGINT[], TEXT, TEXT) TO tools_kernel_app;
