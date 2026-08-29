-- Feature Flag Admin Database Schema
-- Generated from apps/feature-flag-admin/app.yaml

-- Create feature_flag schema
CREATE SCHEMA IF NOT EXISTS feature_flag;

-- Main feature flags table
CREATE TABLE feature_flag.feature_flags (
    flag_key TEXT PRIMARY KEY,
    description TEXT NOT NULL,
    environment TEXT NOT NULL CHECK (environment IN ('desenvolvimento', 'homologacao', 'producao')),
    is_active BOOLEAN NOT NULL DEFAULT false,
    owning_team TEXT NOT NULL,
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
CREATE INDEX idx_feature_flags_environment ON feature_flag.feature_flags(environment) WHERE deleted_at IS NULL;
CREATE INDEX idx_feature_flags_team ON feature_flag.feature_flags(owning_team) WHERE deleted_at IS NULL;
CREATE INDEX idx_feature_flags_is_active ON feature_flag.feature_flags(is_active) WHERE deleted_at IS NULL;
CREATE INDEX idx_feature_flags_active ON feature_flag.feature_flags(created_at DESC) WHERE deleted_at IS NULL;

-- Attach soft delete protection
SELECT create_soft_delete_table('feature_flag.feature_flags', 10, 'compliance-data-retention-policy');
SELECT attach_soft_delete_protection('feature_flag.feature_flags');

-- Enable Row Level Security
ALTER TABLE feature_flag.feature_flags ENABLE ROW LEVEL SECURITY;
ALTER TABLE feature_flag.feature_flags FORCE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY feature_flags_select ON feature_flag.feature_flags
    FOR SELECT
    TO tools_kernel_app
    USING (
        (owning_team = current_actor_team() OR has_role('Tech Lead Plataforma'))
        AND (has_role('Engenheiro Plataforma') OR has_role('Tech Lead Plataforma') OR has_role('Leitor Plataforma'))
    );

CREATE POLICY feature_flags_insert ON feature_flag.feature_flags
    FOR INSERT
    TO tools_kernel_app
    WITH CHECK (
        has_role('Engenheiro Plataforma')
        OR has_role('Tech Lead Plataforma')
    );

CREATE POLICY feature_flags_update ON feature_flag.feature_flags
    FOR UPDATE
    TO tools_kernel_app
    USING (
        owning_team = current_actor_team()
        OR has_role('Tech Lead Plataforma')
    )
    WITH CHECK (
        owning_team = current_actor_team()
        OR has_role('Tech Lead Plataforma')
    );

-- Legacy environment migration: map free-text variants to the canonical enum
CREATE OR REPLACE FUNCTION feature_flag.migrate_environment(p_environment TEXT)
RETURNS TEXT AS $$
BEGIN
    RETURN CASE
        WHEN LOWER(TRIM(p_environment)) IN ('producao', 'prod', 'produção') THEN 'producao'
        WHEN LOWER(TRIM(p_environment)) IN ('homologacao', 'homologação', 'hml') THEN 'homologacao'
        WHEN LOWER(TRIM(p_environment)) IN ('desenvolvimento', 'dev', 'des') THEN 'desenvolvimento'
        ELSE 'desenvolvimento'
    END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Updated_at trigger function
CREATE OR REPLACE FUNCTION feature_flag.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Audit trigger function for feature_flags using the natural key (flag_key)
CREATE OR REPLACE FUNCTION feature_flag.feature_flags_audit_trigger()
RETURNS TRIGGER AS $$
DECLARE
    v_payload JSONB;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_payload := to_jsonb(NEW);
        PERFORM create_audit_entry(
            'feature_flag.feature_flags',
            NEW.flag_key,
            'INSERT',
            v_payload
        );
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        v_payload := jsonb_build_object('old', to_jsonb(OLD), 'new', to_jsonb(NEW));
        PERFORM create_audit_entry(
            'feature_flag.feature_flags',
            NEW.flag_key,
            'UPDATE',
            v_payload
        );
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        v_payload := to_jsonb(OLD);
        PERFORM create_audit_entry(
            'feature_flag.feature_flags',
            OLD.flag_key,
            'DELETE',
            v_payload
        );
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Triggers will be attached after seed data loading in seed-data.sql

-- Grant permissions to application role
GRANT USAGE ON SCHEMA feature_flag TO tools_kernel_app;
GRANT SELECT, INSERT, UPDATE ON feature_flag.feature_flags TO tools_kernel_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA feature_flag TO tools_kernel_app;
