-- Feature Flag Admin Seed Data
-- ~400 flags across environments, owned by named teams, with legacy variant migration

-- Platform users for testing
CREATE TABLE IF NOT EXISTS users (
    email TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    role TEXT NOT NULL,
    team TEXT
);

INSERT INTO users (email, name, role, team) VALUES
('bruno.martins@thefintechcompany.com.br', 'Bruno Martins', 'Engenheiro Plataforma', 'Platform'),
('carla.silva@thefintechcompany.com.br', 'Carla Silva', 'Engenheiro Plataforma', 'KYC'),
('diego.nunes@thefintechcompany.com.br', 'Diego Nunes', 'Engenheiro Plataforma', 'Refunds'),
('fernanda.lima@thefintechcompany.com.br', 'Fernanda Lima', 'Tech Lead Plataforma', 'Platform'),
('gabriel.santos@thefintechcompany.com.br', 'Gabriel Santos', 'Leitor Plataforma', 'Risk')
ON CONFLICT (email) DO NOTHING;

-- Temporarily drop audit trigger to avoid noise during seed
DROP TRIGGER IF EXISTS feature_flags_audit_trigger ON feature_flag.feature_flags;
DROP TRIGGER IF EXISTS update_feature_flags_updated_at ON feature_flag.feature_flags;

-- Staging table for legacy free-text environment values
CREATE TEMP TABLE feature_flag_legacy_import (
    legacy_flag_key TEXT,
    legacy_environment TEXT,
    description TEXT,
    owning_team TEXT
);

INSERT INTO feature_flag_legacy_import VALUES
('legacy-pix-refund-auto-approve', 'Producao', 'Auto-approve PIX refunds in production', 'Refunds'),
('legacy-kyc-pep-secondary-review', 'prod', 'PEP secondary review gate for KYC', 'KYC'),
('legacy-mobile-killswitch-onboarding', 'producao', 'Killswitch for mobile onboarding flow', 'Mobile'),
('legacy-lending-credit-fasttrack', 'Producao', 'Fast-track credit decision in lending', 'Lending'),
('legacy-risk-fraud-score-v2', 'prod', 'Enable fraud score model v2', 'Risk');

-- Migrate legacy flags using the normalization function
INSERT INTO feature_flag.feature_flags (
    flag_key, description, environment, is_active, owning_team, created_by
)
SELECT
    legacy_flag_key,
    description,
    feature_flag.migrate_environment(legacy_environment),
    (random() < 0.3),
    owning_team,
    'migration.legacy'
FROM feature_flag_legacy_import
ON CONFLICT (flag_key) DO NOTHING;

-- Generate 395 additional canonical flags
INSERT INTO feature_flag.feature_flags (
    flag_key, description, environment, is_active, owning_team, created_by
)
SELECT
    'ff-' || i || '-' || keys[(i % 20) + 1],
    'Controls ' || REPLACE(keys[(i % 20) + 1], '-', ' ') || ' (' || teams[(i % 7) + 1] || ')',
    envs[(i % 3) + 1],
    (random() < 0.4),
    teams[(i % 7) + 1],
    'system.seed'
FROM generate_series(1, 395) AS i,
LATERAL (
    SELECT
        ARRAY['desenvolvimento', 'homologacao', 'producao'] AS envs,
        ARRAY['Platform', 'KYC', 'Refunds', 'Payments', 'Lending', 'Risk', 'Data'] AS teams,
        ARRAY[
            'pix-refund-auto-approve',
            'kyc-pep-secondary-review',
            'mobile-killswitch-onboarding',
            'lending-credit-fasttrack',
            'risk-fraud-score-v2',
            'api-rate-limit-bypass',
            'web-dark-mode',
            'checkout-3ds-challenge',
            'data-analytics-consent',
            'infra-circuit-breaker',
            'notifications-push-preference',
            'identity-biometric-fallback',
            'payments-pix-qrcode-dynamic',
            'platform-maintenance-mode',
            'lending-proactive-limit-increase',
            'risk-velocity-check',
            'kyc-document-ocr-fallback',
            'refunds-manual-approval-bypass',
            'api-version-2026-08',
            'web-onboarding-simplified'
        ] AS keys
) p
ON CONFLICT (flag_key) DO NOTHING;

-- Re-enable triggers for normal operations
CREATE TRIGGER feature_flags_audit_trigger
    AFTER INSERT OR UPDATE OR DELETE ON feature_flag.feature_flags
    FOR EACH ROW EXECUTE FUNCTION feature_flag.feature_flags_audit_trigger();

CREATE TRIGGER update_feature_flags_updated_at
    BEFORE UPDATE ON feature_flag.feature_flags
    FOR EACH ROW EXECUTE FUNCTION feature_flag.update_updated_at();

-- Grant permissions on users table
GRANT SELECT ON users TO tools_kernel_app;
