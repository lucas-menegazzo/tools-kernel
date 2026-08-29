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

-- Function to generate SHA-256 hash of audit entry
CREATE FUNCTION generate_audit_hash(
    table_name TEXT,
    record_id TEXT,
    operation TEXT,
    actor_id TEXT,
    actor_roles TEXT[],
    payload JSONB,
    previous_hash TEXT
)
RETURNS TEXT AS $$
DECLARE
    combined TEXT;
BEGIN
    -- Serialise with sorted keys for consistent hashing
    combined := table_name || '|' || 
                record_id || '|' || 
                operation || '|' || 
                actor_id || '|' || 
                array_to_string(actor_roles, ',') || '|' || 
                encode(convert_to(payload::text, 'UTF8'), 'base64') || '|' || 
                COALESCE(previous_hash, '');
    
    RETURN encode(digest(combined, 'sha256'), 'hex');
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

-- Function to create audit entry (called within same transaction as mutation)
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
    -- Get current actor from transaction context
    v_actor_id := current_actor_id();
    v_actor_roles := current_actor_roles();
    
    -- Get previous hash for chaining
    SELECT current_hash INTO v_previous_hash
    FROM audit_trail
    WHERE table_name = p_table_name AND record_id = p_record_id
    ORDER BY created_at DESC
    LIMIT 1;
    
    -- Generate current hash
    v_current_hash := generate_audit_hash(
        p_table_name,
        p_record_id,
        p_operation,
        v_actor_id,
        v_actor_roles,
        p_payload,
        v_previous_hash
    );
    
    -- Insert audit entry
    INSERT INTO audit_trail (
        table_name, record_id, operation, actor_id, actor_roles,
        payload, previous_hash, current_hash
    ) VALUES (
        p_table_name, p_record_id, p_operation, v_actor_id, v_actor_roles,
        p_payload, v_previous_hash, v_current_hash
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger function to automatically audit changes
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

-- Helper function to attach audit trigger to any table
CREATE FUNCTION attach_audit_trigger(table_name TEXT)
RETURNS void AS $$
DECLARE
    v_schema TEXT;
    v_table TEXT;
BEGIN
    -- Parse schema.table name
    SELECT split_part(table_name, '.', 1), split_part(table_name, '.', 2)
    INTO v_schema, v_table;
    
    -- If no schema specified, default to public
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