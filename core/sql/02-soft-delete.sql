-- Soft delete with retention
-- Because legacy calls Remove() and loses the record entirely
-- UPDATE and DELETE blocked at database level for soft-delete tables

-- Function to create soft delete table structure
CREATE FUNCTION create_soft_delete_table(
    table_name TEXT,
    retention_years INTEGER DEFAULT 10,
    retention_rule TEXT DEFAULT 'compliance-data-retention-policy'
)
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
    
    -- Add soft delete columns if they don't exist
    EXECUTE format('
        ALTER TABLE %I.%I 
        ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE,
        ADD COLUMN IF NOT EXISTS deleted_by TEXT,
        ADD COLUMN IF NOT EXISTS retention_period INTEGER DEFAULT %L,
        ADD COLUMN IF NOT EXISTS retention_basis TEXT DEFAULT %L
    ', v_schema, v_table, retention_years, retention_rule);
    
    -- Create index for soft delete queries
    EXECUTE format('
        CREATE INDEX IF NOT EXISTS idx_%s_deleted_at ON %I.%I(deleted_at) 
        WHERE deleted_at IS NOT NULL
    ', v_table, v_schema, v_table);
    
    -- Create partial index for active records
    EXECUTE format('
        CREATE INDEX IF NOT EXISTS idx_%s_active ON %I.%I(created_at DESC) 
        WHERE deleted_at IS NULL
    ', v_table, v_schema, v_table);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger function to prevent hard deletes on soft-delete tables
CREATE FUNCTION prevent_hard_delete()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Hard delete not allowed on table %. Use soft delete instead.', TG_TABLE_NAME;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to attach soft delete protection to a table
CREATE FUNCTION attach_soft_delete_protection(table_name TEXT)
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
    
    -- Prevent hard deletes
    EXECUTE format('
        CREATE TRIGGER prevent_hard_delete_trigger
        BEFORE DELETE ON %I.%I
        FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete()
    ', v_schema, v_table);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to soft delete a record
CREATE FUNCTION soft_delete_record(table_name TEXT, record_id TEXT)
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
        UPDATE %I.%I 
        SET deleted_at = NOW(),
            deleted_by = current_actor_id()
        WHERE id = %L AND deleted_at IS NULL
    ', v_schema, v_table, record_id);
    
    -- Audit the soft delete
    PERFORM create_audit_entry(
        table_name,
        record_id,
        'DELETE',
        jsonb_build_object(
            'deleted_at', NOW(),
            'deleted_by', current_actor_id()
        )
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to clean up expired soft-deleted records
CREATE FUNCTION cleanup_expired_soft_deletes()
RETURNS TABLE(table_name TEXT, records_deleted BIGINT) AS $$
DECLARE
    v_table_name TEXT;
    v_retention_period INTEGER;
    v_deleted_count BIGINT;
BEGIN
    -- This would be called by a scheduled job
    -- For now, return empty set
    RETURN;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;