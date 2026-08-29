-- Restrictive List Screening Database Schema
-- Generated from apps/restrictive-list-screening/app.yaml
-- Two related entities: alerts and list_matches.

-- Create screening schema
CREATE SCHEMA IF NOT EXISTS screening;

-- Main alerts table
CREATE TABLE screening.alerts (
    id BIGSERIAL PRIMARY KEY,
    alert_id TEXT NOT NULL UNIQUE,
    tax_id TEXT NOT NULL,
    customer_name TEXT NOT NULL,
    screened_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    status TEXT NOT NULL CHECK (status IN ('Aberto', 'Em analise', 'Aguardando aprovacao', 'Fechado', 'Encerrado')),
    assigned_to TEXT NOT NULL,
    team TEXT NOT NULL,
    analysis_deadline TIMESTAMP WITH TIME ZONE NOT NULL,
    created_by TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    -- Soft delete columns
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by TEXT,
    retention_period INTEGER DEFAULT 10,
    retention_basis TEXT DEFAULT 'compliance-data-retention-policy'
);

-- Matches that belong to an alert
CREATE TABLE screening.list_matches (
    id BIGSERIAL PRIMARY KEY,
    match_id TEXT NOT NULL UNIQUE,
    alert_id TEXT NOT NULL REFERENCES screening.alerts(alert_id),
    list_name TEXT NOT NULL CHECK (list_name IN ('CSNU', 'OFAC', 'PEP')),
    matched_name TEXT NOT NULL,
    similarity_score NUMERIC(5,4) NOT NULL CHECK (similarity_score >= 0 AND similarity_score <= 1),
    decision TEXT NOT NULL DEFAULT 'indeterminado' CHECK (decision IN ('indeterminado', 'falso_positivo', 'match_confirmado')),
    justification TEXT,
    created_by TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    -- Soft delete columns
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by TEXT,
    retention_period INTEGER DEFAULT 10,
    retention_basis TEXT DEFAULT 'compliance-data-retention-policy'
);

-- Indexes for performance
CREATE INDEX idx_alerts_status ON screening.alerts(status) WHERE deleted_at IS NULL;
CREATE INDEX idx_alerts_assigned_to ON screening.alerts(assigned_to) WHERE deleted_at IS NULL;
CREATE INDEX idx_alerts_team ON screening.alerts(team) WHERE deleted_at IS NULL;
CREATE INDEX idx_alerts_screened_at ON screening.alerts(screened_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_alerts_active ON screening.alerts(created_at DESC) WHERE deleted_at IS NULL;

CREATE INDEX idx_list_matches_alert_id ON screening.list_matches(alert_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_list_matches_decision ON screening.list_matches(decision) WHERE deleted_at IS NULL;
CREATE INDEX idx_list_matches_score ON screening.list_matches(similarity_score) WHERE deleted_at IS NULL;
CREATE INDEX idx_list_matches_active ON screening.list_matches(created_at DESC) WHERE deleted_at IS NULL;

-- Attach soft delete protection
SELECT create_soft_delete_table('screening.alerts', 10, 'compliance-data-retention-policy');
SELECT attach_soft_delete_protection('screening.alerts');
SELECT create_soft_delete_table('screening.list_matches', 10, 'compliance-data-retention-policy');
SELECT attach_soft_delete_protection('screening.list_matches');

-- Enable Row Level Security
ALTER TABLE screening.alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE screening.alerts FORCE ROW LEVEL SECURITY;
ALTER TABLE screening.list_matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE screening.list_matches FORCE ROW LEVEL SECURITY;

-- RLS Policies on alerts
CREATE POLICY alerts_select ON screening.alerts
    FOR SELECT
    TO tools_kernel_app
    USING (
        (assigned_to = current_actor_id() OR team = current_actor_team() OR has_role('Gerente Compliance'))
        AND (has_role('Analista Compliance') OR has_role('Supervisor Compliance') OR has_role('Gerente Compliance'))
    );

CREATE POLICY alerts_insert ON screening.alerts
    FOR INSERT
    TO tools_kernel_app
    WITH CHECK (
        has_role('Analista Compliance') OR has_role('Supervisor Compliance') OR has_role('Gerente Compliance')
    );

CREATE POLICY alerts_update ON screening.alerts
    FOR UPDATE
    TO tools_kernel_app
    USING (
        assigned_to = current_actor_id() OR team = current_actor_team() OR has_role('Gerente Compliance')
    )
    WITH CHECK (
        assigned_to = current_actor_id() OR team = current_actor_team() OR has_role('Gerente Compliance')
    );

-- Cascade RLS: a match is visible only through its parent alert
CREATE POLICY list_matches_select ON screening.list_matches
    FOR SELECT
    TO tools_kernel_app
    USING (
        EXISTS (
            SELECT 1 FROM screening.alerts a
            WHERE a.alert_id = list_matches.alert_id
              AND (a.assigned_to = current_actor_id()
                   OR a.team = current_actor_team()
                   OR has_role('Gerente Compliance'))
              AND (has_role('Analista Compliance') OR has_role('Supervisor Compliance') OR has_role('Gerente Compliance'))
        )
    );

CREATE POLICY list_matches_insert ON screening.list_matches
    FOR INSERT
    TO tools_kernel_app
    WITH CHECK (
        has_role('Analista Compliance') OR has_role('Supervisor Compliance') OR has_role('Gerente Compliance')
    );

CREATE POLICY list_matches_update ON screening.list_matches
    FOR UPDATE
    TO tools_kernel_app
    USING (
        EXISTS (
            SELECT 1 FROM screening.alerts a
            WHERE a.alert_id = list_matches.alert_id
              AND (a.assigned_to = current_actor_id()
                   OR a.team = current_actor_team()
                   OR has_role('Gerente Compliance'))
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM screening.alerts a
            WHERE a.alert_id = list_matches.alert_id
              AND (a.assigned_to = current_actor_id()
                   OR a.team = current_actor_team()
                   OR has_role('Gerente Compliance'))
        )
    );

-- PII masking for names (app-specific; the kernel provides cpf/email/phone)
CREATE OR REPLACE FUNCTION screening.mask_name(name TEXT, show_full_pii BOOLEAN DEFAULT false)
RETURNS TEXT AS $$
BEGIN
    IF show_full_pii OR name IS NULL OR name = '' THEN
        RETURN name;
    END IF;
    RETURN LEFT(name, 1) || '***';
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Aggregate queue view: alerts with count of undecided matches
CREATE OR REPLACE VIEW screening.alert_queue
WITH (security_invoker = on)
AS
SELECT
    a.id,
    a.alert_id,
    a.screened_at,
    a.status,
    a.assigned_to,
    a.team,
    a.analysis_deadline,
    mask_cpf(a.tax_id, can_reveal_pii()) AS tax_id,
    screening.mask_name(a.customer_name, can_reveal_pii()) AS customer_name,
    COUNT(m.id) FILTER (WHERE m.decision = 'indeterminado') AS undecided_matches
FROM screening.alerts a
LEFT JOIN screening.list_matches m ON m.alert_id = a.alert_id AND m.deleted_at IS NULL
WHERE a.deleted_at IS NULL
GROUP BY a.id, a.alert_id, a.screened_at, a.status, a.assigned_to, a.team, a.analysis_deadline, a.tax_id, a.customer_name;

-- Updated_at trigger function
CREATE OR REPLACE FUNCTION screening.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Per-match approval check (uses the approvals table directly)
CREATE OR REPLACE FUNCTION screening.match_has_approval(p_match_id TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM approvals
        WHERE target_table = 'screening.list_matches'
          AND target_record_id = p_match_id
          AND decision = 'approved'
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- Closure validation: alert cannot close if any match is undecided or if a true match lacks approval
CREATE OR REPLACE FUNCTION screening.check_alert_closure()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status IN ('Fechado', 'Encerrado') THEN
        -- No undecided matches
        IF EXISTS (
            SELECT 1 FROM screening.list_matches m
            WHERE m.alert_id = NEW.alert_id
              AND m.decision = 'indeterminado'
              AND m.deleted_at IS NULL
        ) THEN
            RAISE EXCEPTION 'Alert % cannot close while a match is still undecided', NEW.alert_id;
        END IF;

        -- Every confirmed true match must be approved
        IF EXISTS (
            SELECT 1 FROM screening.list_matches m
            WHERE m.alert_id = NEW.alert_id
              AND m.decision = 'match_confirmado'
              AND m.deleted_at IS NULL
              AND NOT screening.match_has_approval(m.match_id)
        ) THEN
            RAISE EXCEPTION 'Alert % cannot close: a confirmed true match lacks approval', NEW.alert_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Configure approval band for matches
INSERT INTO approval_bands (band_name, approving_roles, required_approvals, description)
VALUES (
    'screening_match_approval_band',
    ARRAY['Supervisor Compliance', 'Gerente Compliance'],
    1,
    'Confirmed matches require approval by a compliance supervisor or manager'
) ON CONFLICT (band_name) DO NOTHING;

INSERT INTO table_approval_bands (table_name, band_id)
SELECT 'screening.list_matches', id FROM approval_bands WHERE band_name = 'screening_match_approval_band'
ON CONFLICT (table_name) DO NOTHING;

-- Triggers attached after seed data loading in seed-data.sql
-- to avoid generating seed audit noise.

-- Grant permissions to application role
GRANT USAGE ON SCHEMA screening TO tools_kernel_app;
GRANT SELECT, INSERT, UPDATE ON screening.alerts TO tools_kernel_app;
GRANT SELECT, INSERT, UPDATE ON screening.list_matches TO tools_kernel_app;
GRANT SELECT ON screening.alert_queue TO tools_kernel_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA screening TO tools_kernel_app;
GRANT EXECUTE ON FUNCTION screening.mask_name(TEXT, BOOLEAN) TO tools_kernel_app;
GRANT EXECUTE ON FUNCTION screening.update_updated_at() TO tools_kernel_app;
GRANT EXECUTE ON FUNCTION screening.check_alert_closure() TO tools_kernel_app;
GRANT EXECUTE ON FUNCTION screening.match_has_approval(TEXT) TO tools_kernel_app;
