-- KYC Review Queue Seed Data
-- ~4,000 cases with realistic distribution and names

-- First, create users table for testing
CREATE TABLE IF NOT EXISTS users (
    email TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    role TEXT NOT NULL,
    team TEXT
);

-- Insert users with Brazilian names
INSERT INTO users (email, name, role, team) VALUES
-- Reviewers
('marina.alves@thefintechcompany.com.br', 'Marina Alves', 'Analista Compliance', 'Team A'),
('rafael.souza@thefintechcompany.com.br', 'Rafael Souza', 'Analista Compliance', 'Team A'),
('beatriz.lima@thefintechcompany.com.br', 'Beatriz Lima', 'Analista Compliance', 'Team B'),
('tiago.rocha@thefintechcompany.com.br', 'Tiago Rocha', 'Analista Compliance', 'Team B'),
('camila.nunes@thefintechcompany.com.br', 'Camila Nunes', 'Analista Compliance', 'Team A'),
('diego.prado@thefintechcompany.com.br', 'Diego Prado', 'Analista Compliance', 'Team B'),
-- Supervisors
('helena.castro@thefintechcompany.com.br', 'Helena Castro', 'Supervisor Compliance', 'Team A'),
('vitor.camargo@thefintechcompany.com.br', 'Vitor Camargo', 'Supervisor Compliance', 'Team B'),
-- Compliance Manager
('juliana.prado@thefintechcompany.com.br', 'Juliana Prado', 'Gerente Compliance', 'Management'),
-- CISO (PII access but no case team)
('otavio.branco@thefintechcompany.com.br', 'Otavio Branco', 'CISO', 'Security')
ON CONFLICT (email) DO NOTHING;

-- Function to generate realistic Brazilian CPF (invalid sequences)
CREATE OR REPLACE FUNCTION generate_invalid_cpf()
RETURNS TEXT AS $$
DECLARE
    base_digits TEXT;
    cpf TEXT;
BEGIN
    -- Generate CPF with deliberately invalid sequences
    base_digits := LPAD((random() * 999999)::int::text, 6, '0');
    cpf := base_digits || '000000'; -- Invalid sequence
    RETURN SUBSTRING(cpf FROM 1 FOR 3) || '.' || 
           SUBSTRING(cpf FROM 4 FOR 3) || '.' || 
           SUBSTRING(cpf FROM 7 FOR 3) || '-' || 
           SUBSTRING(cpf FROM 10 FOR 2);
END;
$$ LANGUAGE plpgsql;

-- Function to generate realistic Brazilian names
CREATE OR REPLACE FUNCTION generate_brazilian_name()
RETURNS TEXT AS $$
DECLARE
    first_names TEXT[] := ARRAY[
        'Ana', 'Bruna', 'Carla', 'Daniela', 'Elena', 'Fernanda', 'Gabriela', 'Helena',
        'Isabela', 'Juliana', 'Larissa', 'Marina', 'Natasha', 'Olivia', 'Patricia',
        'Quiteria', 'Renata', 'Sabrina', 'Tatiana', 'Ursula', 'Vanessa', 'William',
        'Xuxa', 'Yara', 'Zelia', 'Antonio', 'Bruno', 'Carlos', 'Diego', 'Eduardo',
        'Felipe', 'Gabriel', 'Henrique', 'Igor', 'Joao', 'Kaio', 'Lucas', 'Mateus',
        'Nicolas', 'Otavio', 'Pedro', 'Quintino', 'Rafael', 'Samuel', 'Thiago', 'Ulysses',
        'Vinicius', 'William', 'Xavier', 'Yuri', 'Zeca'
    ];
    last_names TEXT[] := ARRAY[
        'Silva', 'Santos', 'Oliveira', 'Souza', 'Lima', 'Pereira', 'Costa', 'Ferreira',
        'Rodrigues', 'Almeida', 'Nascimento', 'Araujo', 'Ribeiro', 'Carvalho', 'Gomes',
        'Martins', 'Rocha', 'Barbosa', 'Alves', 'Nunes', 'Campos', 'Moreira', 'Mendes'
    ];
BEGIN
    RETURN (first_names[floor(random() * array_length(first_names, 1)) + 1] || ' ' ||
            last_names[floor(random() * array_length(last_names, 1)) + 1] || ' ' ||
            last_names[floor(random() * array_length(last_names, 1)) + 1]);
END;
$$ LANGUAGE plpgsql;

-- Generate case numbers with realistic distribution
CREATE OR REPLACE FUNCTION generate_case_number()
RETURNS TEXT AS $$
BEGIN
    RETURN 'KYC-' || LPAD((random() * 99999)::int::text, 5, '0') || '-' || 
           TO_CHAR(NOW() - (random() * INTERVAL '90 days'), 'YYYY') || '-' ||
           LPAD((random() * 999)::int::text, 3, '0');
END;
$$ LANGUAGE plpgsql;

-- Disable triggers for seed data loading
DROP TRIGGER IF EXISTS enforce_qualification_deadline ON kyc.kyc_cases;
DROP TRIGGER IF EXISTS audit_trigger ON kyc.kyc_cases;
DROP TRIGGER IF EXISTS prevent_hard_delete_trigger ON kyc.kyc_cases;
DROP TRIGGER IF EXISTS update_kyc_cases_updated_at ON kyc.kyc_cases;

-- Insert seed data with realistic distribution
INSERT INTO kyc.kyc_cases (
    case_number, cpf, full_name, risk_level, status, 
    responsible_analyst, opened_at, qualification_deadline, 
    analysis_result, team, created_by
)
SELECT 
    generate_case_number(),
    generate_invalid_cpf(),
    generate_brazilian_name(),
    CASE 
        WHEN random() < 0.60 THEN 'Baixo'    -- 60% low risk
        WHEN random() < 0.85 THEN 'Medio'    -- 25% medium risk  
        WHEN random() < 0.98 THEN 'Alto'     -- 13% high risk
        ELSE 'PEP'                           -- 2% PEP
    END,
    CASE 
        WHEN random() < 0.70 THEN 'Em analise'         -- 70% in analysis
        WHEN random() < 0.85 THEN 'Aguardando aprovacao' -- 15% awaiting approval
        WHEN random() < 0.95 THEN 'Novo'                -- 10% new
        ELSE 'Encerrado'                               -- 5% closed
    END,
    CASE 
        WHEN random() < 0.33 THEN 'marina.alves@thefintechcompany.com.br'
        WHEN random() < 0.66 THEN 'rafael.souza@thefintechcompany.com.br'
        WHEN random() < 0.50 THEN 'beatriz.lima@thefintechcompany.com.br'
        WHEN random() < 0.75 THEN 'tiago.rocha@thefintechcompany.com.br'
        WHEN random() < 0.90 THEN 'camila.nunes@thefintechcompany.com.br'
        ELSE 'diego.prado@thefintechcompany.com.br'
    END,
    NOW() - (random() * INTERVAL '90 days'), -- Opened in last 90 days
    NOW() + CASE 
        WHEN random() < 0.10 THEN -INTERVAL '5 days'    -- 10% overdue
        WHEN random() < 0.25 THEN INTERVAL '3 days'    -- 15% due this week
        ELSE INTERVAL '20 days'                       -- 75% fine
    END,
    CASE 
        WHEN random() < 0.5 THEN 'Análise preliminar concluída'
        WHEN random() < 0.75 THEN 'Documentação adicional necessária'
        ELSE 'Aguardando confirmação de renda'
    END,
    CASE 
        WHEN random() < 0.5 THEN 'Team A'
        ELSE 'Team B'
    END,
    'system.seed'
FROM generate_series(1, 4000);

-- Update some cases to have proper qualification deadlines (30 days from opening)
UPDATE kyc.kyc_cases 
SET qualification_deadline = opened_at + INTERVAL '30 days'
WHERE qualification_deadline < opened_at;

-- Set some cases as overdue
UPDATE kyc.kyc_cases 
SET qualification_deadline = NOW() - INTERVAL '5 days'
WHERE random() < 0.02; -- ~80 cases overdue

-- Set some cases as due this week
UPDATE kyc.kyc_cases 
SET qualification_deadline = NOW() + INTERVAL '3 days'
WHERE random() < 0.05; -- ~200 cases due this week

-- Insert some already-approved cases for testing
INSERT INTO kyc.kyc_cases (
    case_number, cpf, full_name, risk_level, status, 
    responsible_analyst, opened_at, qualification_deadline, 
    analysis_result, team, created_by
)
SELECT 
    'KYC-APPROVED-' || LPAD(i::text, 5, '0') || '-2026-' || LPAD((random() * 999)::int::text, 3, '0'),
    generate_invalid_cpf(),
    generate_brazilian_name(),
    'Baixo',
    'Aprovado',
    'marina.alves@thefintechcompany.com.br',
    NOW() - INTERVAL '60 days',
    NOW() - INTERVAL '35 days',
    'Case approved after review',
    'Team A',
    'system.seed'
FROM generate_series(1, 100) AS i;

-- Re-enable triggers for normal operations
CREATE TRIGGER enforce_qualification_deadline
    BEFORE INSERT OR UPDATE OF qualification_deadline, opened_at
    ON kyc.kyc_cases
    FOR EACH ROW EXECUTE FUNCTION kyc.check_qualification_deadline();

CREATE TRIGGER update_kyc_cases_updated_at
    BEFORE UPDATE ON kyc.kyc_cases
    FOR EACH ROW EXECUTE FUNCTION kyc.update_updated_at();

SELECT attach_audit_trigger('kyc.kyc_cases');
SELECT attach_soft_delete_protection('kyc.kyc_cases');

-- Grant permissions on users table
GRANT SELECT ON users TO tools_kernel_app;