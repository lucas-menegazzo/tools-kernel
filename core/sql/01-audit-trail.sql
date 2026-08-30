-- Append-only audit trail
-- Every mutation recorded in the SAME transaction as the mutation
-- SHA-256 chained to the previous entry
-- UPDATE and DELETE blocked by database rules, not by convention
-- Payload serialised with sorted keys for chain verification

-- Audit trail table
CREATE TABLE audit_trail (
    id BIGSERIAL PRIMARY KEY,
    table_name TEXT NOT NULL,
    record_id TEXT NOT NULL,
    operation TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    actor_id TEXT NOT NULL,
    actor_roles TEXT[] NOT NULL,
    payload JSONB NOT NULL,
    previous_hash TEXT,
    current_hash TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Index for audit trail queries
CREATE INDEX idx_audit_trail_table_record ON audit_trail(table_name, record_id);
CREATE INDEX idx_audit_trail_created_at ON audit_trail(created_at DESC);

-- Function to generate SHA-256 hash of an audit entry.
-- All inputs are typed, so malformed data is rejected by PostgreSQL before this
-- function is called. actor_roles is normalised to an empty array when NULL and
-- previous_hash defaults to an empty string to keep the chain stable.
CREATE FUNCTION generate_audit_hash(
    p_table_name TEXT,
    p_record_id TEXT,
    p_operation TEXT,
    p_actor_id TEXT,
    p_actor_roles TEXT[],
    p_payload JSONB,
    p_previous_hash TEXT
)
RETURNS TEXT AS $$
DECLARE
    v_combined TEXT;
BEGIN
    -- Guard against NULL values in required fields.
    IF p_table_name IS NULL OR p_record_id IS NULL OR p_operation IS NULL OR
       p_actor_id IS NULL OR p_payload IS NULL THEN
        RAISE EXCEPTION 'generate_audit_hash: table_name, record_id, operation, actor_id and payload are required';
    END IF;

    -- Serialise with sorted keys for consistent hashing.
    v_combined := p_table_name || '|' ||
                  p_record_id || '|' ||
                  p_operation || '|' ||
                  p_actor_id || '|' ||
                  array_to_string(COALESCE(p_actor_roles, ARRAY[]::TEXT[]), ',') || '|' ||
                  encode(convert_to(p_payload::text, 'UTF8'), 'base64') || '|' ||
                  COALESCE(p_previous_hash, '');

    RETURN encode(digest(v_combined, 'sha256'), 'hex');
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Function to create a chained audit entry inside the same transaction as the
-- mutation it records. This keeps the audit table append-only and the hash chain
-- unbroken. It pulls the current actor from the session context set by the app.
CREATE FUNCTION create_audit_entry(
    p_table_name TEXT,
    p_record_id TEXT,
    p_operation TEXT,
    p_payload JSONB
)
RETURNS void AS $$
DECLARE
    v_previous_hash TEXT;
    v_current_hash TEXT;
    v_actor_id TEXT;
    v_actor_roles TEXT[];
BEGIN
    -- Get current actor from transaction context; missing context is an error.
    v_actor_id := current_actor_id();
    v_actor_roles := current_actor_roles();

    IF v_actor_id IS NULL OR v_actor_id = '' THEN
        RAISE EXCEPTION 'create_audit_entry: no actor context is set';
    END IF;

    -- Get previous hash for chaining.
    SELECT current_hash INTO v_previous_hash
    FROM audit_trail
    WHERE table_name = p_table_name AND record_id = p_record_id
    ORDER BY created_at DESC
    LIMIT 1;

    -- Generate current hash.
    v_current_hash := generate_audit_hash(
        p_table_name,
        p_record_id,
        p_operation,
        v_actor_id,
        v_actor_roles,
        p_payload,
        v_previous_hash
    );

    -- Insert audit entry.
    INSERT INTO audit_trail (
        table_name, record_id, operation, actor_id, actor_roles,
        payload, previous_hash, current_hash
    ) VALUES (
        p_table_name, p_record_id, p_operation, v_actor_id, v_actor_roles,
        p_payload, v_previous_hash, v_current_hash
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger function to automatically audit changes.
-- Builds a JSONB payload from the row and records an INSERT, UPDATE or DELETE
-- in the same transaction. It tries 'id' and then 'case_number' for a stable
-- record identifier; if neither exists, it falls back to 'unknown'.
CREATE FUNCTION audit_trigger_function()
RETURNS TRIGGER AS $$
DECLARE
    v_payload JSONB;
    v_record_id TEXT;
BEGIN
    -- Build payload with sorted keys
    IF TG_OP = 'INSERT' THEN
        v_payload := to_jsonb(NEW);
        -- Try to get primary key - first try 'id', then 'case_number', then use the first column
        BEGIN
            v_record_id := (NEW.id)::TEXT;
        EXCEPTION WHEN OTHERS THEN
            BEGIN
                v_record_id := (NEW.case_number)::TEXT;
            EXCEPTION WHEN OTHERS THEN
                v_record_id := 'unknown';
            END;
        END;
        
        PERFORM create_audit_entry(
            TG_TABLE_NAME::TEXT,
            v_record_id,
            'INSERT',
            v_payload
        );
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        v_payload := jsonb_build_object(
            'old', to_jsonb(OLD),
            'new', to_jsonb(NEW)
        );
        -- Try to get primary key
        BEGIN
            v_record_id := (NEW.id)::TEXT;
        EXCEPTION WHEN OTHERS THEN
            BEGIN
                v_record_id := (NEW.case_number)::TEXT;
            EXCEPTION WHEN OTHERS THEN
                v_record_id := 'unknown';
            END;
        END;
        
        PERFORM create_audit_entry(
            TG_TABLE_NAME::TEXT,
            v_record_id,
            'UPDATE',
            v_payload
        );
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        v_payload := to_jsonb(OLD);
        -- Try to get primary key
        BEGIN
            v_record_id := (OLD.id)::TEXT;
        EXCEPTION WHEN OTHERS THEN
            BEGIN
                v_record_id := (OLD.case_number)::TEXT;
            EXCEPTION WHEN OTHERS THEN
                v_record_id := 'unknown';
            END;
        END;
        
        PERFORM create_audit_entry(
            TG_TABLE_NAME::TEXT,
            v_record_id,
            'DELETE',
            v_payload
        );
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper function to attach the audit trigger to any table.
-- Expects a qualified name such as 'kyc.kyc_cases' and uses format() with %I
-- identifiers to prevent SQL injection in the trigger definition.
CREATE FUNCTION attach_audit_trigger(table_name TEXT)
RETURNS void AS $$
DECLARE
    v_schema TEXT;
    v_table TEXT;
BEGIN
    -- Parse schema.table name.
    SELECT split_part(table_name, '.', 1), split_part(table_name, '.', 2)
    INTO v_schema, v_table;

    -- If no schema specified, default to public.
    IF v_table IS NULL OR v_table = '' THEN
        v_table := v_schema;
        v_schema := 'public';
    END IF;

    EXECUTE format('
        CREATE TRIGGER audit_trigger
        AFTER INSERT OR UPDATE OR DELETE ON %I.%I
        FOR EACH ROW EXECUTE FUNCTION audit_trigger_function()
    ', v_schema, v_table);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;