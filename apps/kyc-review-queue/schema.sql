-- KYC Review Queue Database Schema
-- Generated from apps/kyc-review-queue/app.yaml

-- Create kyc schema
CREATE SCHEMA IF NOT EXISTS kyc;

-- Main cases table
CREATE TABLE kyc.kyc_cases (
    case_number TEXT PRIMARY KEY,
    cpf TEXT NOT NULL,
    full_name TEXT NOT NULL,
    risk_level TEXT NOT NULL CHECK (risk_level IN ('Baixo', 'Medio', 'Alto', 'PEP')),
    status TEXT NOT NULL CHECK (status IN ('Novo', 'Em analise', 'Aguardando aprovacao', 'Aprovado', 'Reprovado', 'Comunicado ao Coaf', 'Encerrado')),
    responsible_analyst TEXT,
    opened_at TIMESTAMP WITH TIME ZONE NOT NULL,
    qualification_deadline TIMESTAMP WITH TIME ZONE NOT NULL,
    analysis_result TEXT,
    team TEXT NOT NULL,
    created_by TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    
    -- Soft delete columns
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by TEXT,
    retention_period INTEGER DEFAULT 10,
    retention_basis TEXT DEFAULT 'compliance-data-retention-policy'
);

-- Create indexes for performance
CREATE INDEX idx_kyc_cases_status ON kyc.kyc_cases(status) WHERE deleted_at IS NULL;
CREATE INDEX idx_kyc_cases_responsible_analyst ON kyc.kyc_cases(responsible_analyst) WHERE deleted_at IS NULL;
CREATE INDEX idx_kyc_cases_team ON kyc.kyc_cases(team) WHERE deleted_at IS NULL;
CREATE INDEX idx_kyc_cases_qualification_deadline ON kyc.kyc_cases(qualification_deadline) WHERE deleted_at IS NULL;
CREATE INDEX idx_kyc_cases_risk_level ON kyc.kyc_cases(risk_level) WHERE deleted_at IS NULL;
CREATE INDEX idx_kyc_cases_active ON kyc.kyc_cases(created_at DESC) WHERE deleted_at IS NULL;

-- Attach soft delete protection
SELECT create_soft_delete_table('kyc.kyc_cases', 10, 'compliance-data-retention-policy');
SELECT attach_soft_delete_protection('kyc.kyc_cases');

-- Audit trigger will be attached after seed data loading in seed-data.sql

-- Enable Row Level Security
ALTER TABLE kyc.kyc_cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE kyc.kyc_cases FORCE ROW LEVEL SECURITY;

-- RLS Policies
-- No default policy - defaults to deny all
-- Explicitly grant SELECT access only to compliance roles
CREATE POLICY kyc_cases_select ON kyc.kyc_cases
    FOR SELECT
    TO tools_kernel_app
    USING (
        (has_role('Analista Compliance') AND responsible_analyst = current_actor_id())
        OR (has_role('Supervisor Compliance') AND team = current_actor_team())
        OR has_role('Gerente Compliance')
    );

CREATE POLICY kyc_cases_insert ON kyc.kyc_cases
    FOR INSERT
    TO tools_kernel_app
    WITH CHECK (
        has_role('Analista Compliance') 
        OR has_role('Supervisor Compliance') 
        OR has_role('Gerente Compliance')
    );

CREATE POLICY kyc_cases_update ON kyc.kyc_cases
    FOR UPDATE
    TO tools_kernel_app
    USING (
        (responsible_analyst = current_actor_id() 
        OR has_role('Supervisor Compliance') 
        OR has_role('Gerente Compliance'))
    )
    WITH CHECK (
        (responsible_analyst = current_actor_id() 
        OR has_role('Supervisor Compliance') 
        OR has_role('Gerente Compliance'))
    );

-- Configure approval band for KYC cases
INSERT INTO approval_bands (band_name, approving_roles, required_approvals, description)
VALUES (
    'kyc_approval_band',
    ARRAY['Supervisor Compliance', 'Gerente Compliance'],
    1,
    'KYC cases require single approval from supervisor or manager'
) ON CONFLICT (band_name) DO NOTHING;

INSERT INTO table_approval_bands (table_name, band_id)
SELECT 'kyc.kyc_cases', id FROM approval_bands WHERE band_name = 'kyc_approval_band'
ON CONFLICT (table_name) DO NOTHING;

-- Function to enforce 30-day qualification deadline
CREATE FUNCTION kyc.check_qualification_deadline()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.qualification_deadline > NEW.opened_at + INTERVAL '30 days' THEN
        RAISE EXCEPTION 'Qualification deadline cannot exceed 30 days from opening date';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers will be created after seed data loading in seed-data.sql

-- Updated_at trigger function
CREATE FUNCTION kyc.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Grant permissions to application role
GRANT USAGE ON SCHEMA kyc TO tools_kernel_app;
GRANT SELECT, INSERT, UPDATE ON kyc.kyc_cases TO tools_kernel_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA kyc TO tools_kernel_app;