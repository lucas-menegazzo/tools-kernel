-- Refunds Dashboard seed data
-- 3,000 refunds spread across all three amount bands

-- Create helper functions
CREATE OR REPLACE FUNCTION refunds.generate_brazilian_name()
RETURNS TEXT AS $$
DECLARE
    first_names TEXT[] := ARRAY[
        'Larissa', 'Bruno', 'Fernanda', 'Igor', 'Paula', 'Ricardo', 'Marina', 'Tiago',
        'Beatriz', 'Camila', 'Diego', 'Rafael', 'Helena', 'Otavio', 'Elena', 'Kaio'
    ];
    last_names TEXT[] := ARRAY[
        'Melo', 'Tavares', 'Reis', 'Salgado', 'Werneck', 'Salles', 'Alves', 'Souza',
        'Lima', 'Rocha', 'Nunes', 'Prado', 'Castro', 'Branco', 'Costa', 'Martins'
    ];
BEGIN
    RETURN first_names[(1 + floor(random() * array_length(first_names, 1)))::int] || ' ' ||
           last_names[(1 + floor(random() * array_length(last_names, 1)))::int] || ' ' ||
           last_names[(1 + floor(random() * array_length(last_names, 1)))::int];
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION refunds.generate_invalid_cpf()
RETURNS TEXT AS $$
DECLARE
    digits TEXT;
BEGIN
    digits := '';
    FOR i IN 1..11 LOOP
        digits := digits || (random() * 9)::int::text;
    END LOOP;
    RETURN SUBSTRING(digits FROM 1 FOR 3) || '.' ||
           SUBSTRING(digits FROM 4 FOR 3) || '.' ||
           SUBSTRING(digits FROM 7 FOR 3) || '-' ||
           SUBSTRING(digits FROM 10 FOR 2);
END;
$$ LANGUAGE plpgsql;

-- Names of operations team members and their teams
CREATE TABLE IF NOT EXISTS refunds.requesters (
    email TEXT PRIMARY KEY,
    name TEXT,
    team TEXT
);

TRUNCATE refunds.requesters RESTART IDENTITY;
INSERT INTO refunds.requesters (email, name, team) VALUES
    ('larissa.melo@thefintechcompany.com.br', 'Larissa Melo', 'Operacoes'),
    ('bruno.tavares@thefintechcompany.com.br', 'Bruno Tavares', 'Operacoes'),
    ('fernanda.reis@thefintechcompany.com.br', 'Fernanda Reis', 'Operacoes'),
    ('igor.salgado@thefintechcompany.com.br', 'Igor Salgado', 'Operacoes');

-- Disable triggers before bulk seed to avoid audit context issues
DROP TRIGGER IF EXISTS audit_trigger ON refunds.devolucoes;
DROP TRIGGER IF EXISTS prevent_hard_delete_trigger ON refunds.devolucoes;
DROP TRIGGER IF EXISTS update_devolucoes_updated_at ON refunds.devolucoes;

-- Insert 3,000 refunds with amounts spread across all bands
INSERT INTO refunds.devolucoes (
    case_number, cpf_cliente, nome_cliente, valor, motivo, status,
    solicitado_por, solicitada_em, team, created_by
)
SELECT
    'REF-' || LPAD(i::text, 8, '0') || '-2026',
    refunds.generate_invalid_cpf(),
    refunds.generate_brazilian_name(),
    CASE
        WHEN i % 10 IN (0,1,2,3) THEN (random() * 4999.99 + 0.01)::NUMERIC(19,2)  -- ~40% below 5k
        WHEN i % 10 IN (4,5,6,7) THEN (random() * 44999.99 + 5000)::NUMERIC(19,2)  -- ~40% 5k-50k
        ELSE (random() * 150000 + 50000.01)::NUMERIC(19,2)  -- ~20% above 50k
    END,
    (ARRAY['Cobranca indevida', 'Produto nao entregue', 'Fraude confirmada', 'Duplicidade', 'Outro'])[(1 + floor(random() * 5))::int],
    'Solicitada',
    (ARRAY[
        'larissa.melo@thefintechcompany.com.br',
        'bruno.tavares@thefintechcompany.com.br',
        'fernanda.reis@thefintechcompany.com.br',
        'igor.salgado@thefintechcompany.com.br'
    ])[(i % 4) + 1],
    NOW() - (random() * INTERVAL '90 days'),
    'Operacoes',
    (ARRAY[
        'larissa.melo@thefintechcompany.com.br',
        'bruno.tavares@thefintechcompany.com.br',
        'fernanda.reis@thefintechcompany.com.br',
        'igor.salgado@thefintechcompany.com.br'
    ])[(i % 4) + 1]
FROM generate_series(1, 3000) AS i;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_devolucoes_case_number ON refunds.devolucoes(case_number);

-- Re-enable triggers
SELECT attach_audit_trigger('refunds.devolucoes');
SELECT attach_soft_delete_protection('refunds.devolucoes');

CREATE TRIGGER update_devolucoes_updated_at
    BEFORE UPDATE ON refunds.devolucoes
    FOR EACH ROW EXECUTE FUNCTION refunds.update_devolucoes_updated_at();

-- Grant permissions on requesters table
GRANT SELECT ON refunds.requesters TO tools_kernel_app;
