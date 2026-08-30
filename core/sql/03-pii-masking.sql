-- PII masking by role
-- Applied as the value leaves the data layer
-- Based on roles defined in AGENTS.md

-- Mask a CPF (Brazilian tax ID).
-- If show_full_pii is true or the value is missing, return it unchanged.
-- Otherwise return XXX.***.***-XX, preserving the last two digits.
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

-- Mask an email address as u***@domain.com.
-- If show_full_pii is true or the value is missing, return it unchanged.
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

-- Mask a phone number as (XX) *****-XXXX.
-- If show_full_pii is true or the value is missing, return it unchanged.
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

-- Return true if the current actor has a role that is allowed to see full PII.
-- This is the single gate used by every masking function and masked view.
CREATE FUNCTION can_reveal_pii()
RETURNS BOOLEAN AS $$
BEGIN
    -- Only specific roles can reveal PII
    -- This should be configured based on actual roles
    RETURN has_role('CISO') OR has_role('ComplianceManager') OR has_role('DataProtectionOfficer');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Generic PII masking dispatcher.
-- Given a value and its type (cpf, email, phone), calls the appropriate
-- masking function using the current actor's can_reveal_pii() status.
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

-- Create or replace a view that masks the given PII columns.
-- The source view must already exist. One masked view is created per listed
-- column. Uses can_reveal_pii() to decide whether to show the raw value.
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