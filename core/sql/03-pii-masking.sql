-- PII masking by role
-- Applied as the value leaves the data layer
-- Based on roles defined in AGENTS.md

-- Masking function for CPF (Brazilian tax ID)
CREATE FUNCTION mask_cpf(cpf TEXT, show_full_pii BOOLEAN DEFAULT false)
RETURNS TEXT AS $$
DECLARE
    digits TEXT;
BEGIN
    IF show_full_pii OR cpf IS NULL OR cpf = '' THEN
        RETURN cpf;
    END IF;
    
    -- Extract only digits to handle both formatted and raw CPFs
    digits := REGEXP_REPLACE(cpf, '\D', '', 'g');
    
    IF LENGTH(digits) < 11 THEN
        RETURN '***.***.***-**';
    END IF;
    
    -- Mask as XXX.***.***-XX
    RETURN SUBSTRING(digits FROM 1 FOR 3) || '.***.***-' || SUBSTRING(digits FROM 10 FOR 2);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

-- Masking function for email
CREATE FUNCTION mask_email(email TEXT, show_full_pii BOOLEAN DEFAULT false)
RETURNS TEXT AS $$
BEGIN
    IF show_full_pii OR email IS NULL OR email = '' THEN
        RETURN email;
    END IF;
    
    -- Mask as u***@domain.com
    RETURN SUBSTRING(email FROM 1 FOR 1) || '***@' || SUBSTRING(email FROM POSITION('@' IN email) + 1);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

-- Masking function for phone
CREATE FUNCTION mask_phone(phone TEXT, show_full_pii BOOLEAN DEFAULT false)
RETURNS TEXT AS $$
BEGIN
    IF show_full_pii OR phone IS NULL OR phone = '' THEN
        RETURN phone;
    END IF;
    
    -- Mask as (XX) XXXXX-XXXX
    RETURN REGEXP_REPLACE(phone, '(\d{2})\d{5}(\d{4})', '(\1) *****-\2');
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

-- Check if current actor has PII revelation permission
CREATE FUNCTION can_reveal_pii()
RETURNS BOOLEAN AS $$
BEGIN
    -- Only specific roles can reveal PII
    -- This should be configured based on actual roles
    RETURN has_role('CISO') OR has_role('ComplianceManager') OR has_role('DataProtectionOfficer');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Generic PII masking function based on field type
CREATE FUNCTION mask_pii(field_value TEXT, field_type TEXT DEFAULT 'cpf')
RETURNS TEXT AS $$
BEGIN
    CASE field_type
        WHEN 'cpf' THEN RETURN mask_cpf(field_value, can_reveal_pii());
        WHEN 'email' THEN RETURN mask_email(field_value, can_reveal_pii());
        WHEN 'phone' THEN RETURN mask_phone(field_value, can_reveal_pii());
        ELSE RETURN field_value;
    END CASE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Column-level security example for CPF field
-- This would be applied to views that expose PII data
CREATE FUNCTION apply_pii_masking_to_view(view_name TEXT, pii_columns TEXT[])
RETURNS void AS $$
DECLARE
    v_column TEXT;
BEGIN
    FOREACH v_column IN ARRAY pii_columns
    LOOP
        EXECUTE format('
            CREATE OR REPLACE VIEW %I AS
            SELECT 
                %s,
                CASE WHEN can_reveal_pii() THEN %s ELSE mask_pii(%s::text, %L) END AS %s
            FROM %I
        ', view_name, '*', v_column, v_column, 'cpf', v_column, view_name);
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;