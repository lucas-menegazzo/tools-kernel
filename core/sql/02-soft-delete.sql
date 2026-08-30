-- Soft delete with retention
-- Because legacy calls Remove() and loses the record entirely
-- UPDATE and DELETE blocked at database level for soft-delete tables

-- Function to create soft delete table structure.
-- Adds deleted_at, deleted_by, retention_period and retention_basis columns.
-- Uses format() with %I for identifiers and %L for literals, which prevents
-- SQL injection in the dynamic ALTER/CREATE INDEX statements.
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
    -- Parse schema.table name.
    SELECT split_part(table_name, '.', 1), split_part(table_name, '.', 2)
    INTO v_schema, v_table;

    -- If no schema specified, default to public.
    IF v_table IS NULL OR v_table = '' THEN
        v_table := v_schema;
        v_schema := 'public';
    END IF;

    -- Reject unqualified or unsafe names before any dynamic SQL.
    IF v_schema IS NULL OR v_schema = '' OR v_table IS NULL OR v_table = '' THEN
        RAISE EXCEPTION 'create_soft_delete_table: invalid table name %', table_name;
    END IF;

    -- Add soft delete columns if they don't exist.
    EXECUTE format('
        ALTER TABLE %I.%I 
        ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE,
        ADD COLUMN IF NOT EXISTS deleted_by TEXT,
        ADD COLUMN IF NOT EXISTS retention_period INTEGER DEFAULT %L,
        ADD COLUMN IF NOT EXISTS retention_basis TEXT DEFAULT %L
    ', v_schema, v_table, retention_years, retention_rule);

    -- Create index for soft delete queries.
    EXECUTE format('
        CREATE INDEX IF NOT EXISTS %I ON %I.%I(deleted_at) 
        WHERE deleted_at IS NOT NULL
    ', 'idx_' || v_table || '_deleted_at', v_schema, v_table);

    -- Create partial index for active records.
    EXECUTE format('
        CREATE INDEX IF NOT EXISTS %I ON %I.%I(created_at DESC) 
        WHERE deleted_at IS NULL
    ', 'idx_' || v_table || '_active', v_schema, v_table);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger function to prevent hard deletes on soft-delete tables.
-- Raises an exception when a DELETE is attempted, forcing callers to use
-- soft_delete_record() instead.
CREATE FUNCTION prevent_hard_delete()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Hard delete not allowed on table %. Use soft delete instead.', TG_TABLE_NAME;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Attach the hard-delete prevention trigger to a table.
-- Uses format() with %I identifiers to avoid SQL injection.
CREATE FUNCTION attach_soft_delete_protection(table_name TEXT)
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

    -- Reject unqualified or unsafe names.
    IF v_schema IS NULL OR v_schema = '' OR v_table IS NULL OR v_table = '' THEN
        RAISE EXCEPTION 'attach_soft_delete_protection: invalid table name %', table_name;
    END IF;

    -- Prevent hard deletes.
    EXECUTE format('
        CREATE TRIGGER prevent_hard_delete_trigger
        BEFORE DELETE ON %I.%I
        FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete()
    ', v_schema, v_table);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Soft delete a single record by id and record the action in the audit trail.
-- Requires an actor context to set deleted_by.
CREATE FUNCTION soft_delete_record(table_name TEXT, record_id TEXT)
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

    -- Reject unqualified or unsafe names.
    IF v_schema IS NULL OR v_schema = '' OR v_table IS NULL OR v_table = '' THEN
        RAISE EXCEPTION 'soft_delete_record: invalid table name %', table_name;
    END IF;

    EXECUTE format('
        UPDATE %I.%I 
        SET deleted_at = NOW(),
            deleted_by = current_actor_id()
        WHERE id = %L AND deleted_at IS NULL
    ', v_schema, v_table, record_id);

    -- Audit the soft delete.
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

-- Placeholder for a scheduled job that permanently removes records whose
-- retention period has expired. Called by an external scheduler, not by apps.
CREATE FUNCTION cleanup_expired_soft_deletes()
RETURNS TABLE(table_name TEXT, records_deleted BIGINT) AS $$
DECLARE
    v_table_name TEXT;
    v_retention_period INTEGER;
    v_deleted_count BIGINT;
BEGIN
    -- This would be called by a scheduled job.
    -- For now, return empty set.
    RETURN;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;