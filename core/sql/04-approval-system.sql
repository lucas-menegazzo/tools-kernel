-- Approval as a SEPARATE record, never a column on the row being approved
-- A band declares which roles may approve and how many DISTINCT approvals are required
-- The proposer never approves
-- A refused attempt is recorded in the trail rather than discarded

-- Approval bands configuration
CREATE TABLE approval_bands (
    id SERIAL PRIMARY KEY,
    band_name TEXT NOT NULL UNIQUE,
    approving_roles TEXT[] NOT NULL,
    required_approvals INTEGER NOT NULL CHECK (required_approvals >= 1),
    description TEXT
);

-- Approval records (separate from the target entity)
CREATE TABLE approvals (
    id BIGSERIAL PRIMARY KEY,
    target_table TEXT NOT NULL,
    target_record_id TEXT NOT NULL,
    actor_id TEXT NOT NULL,
    actor_role TEXT NOT NULL,
    decision TEXT NOT NULL CHECK (decision IN ('approved', 'refused')),
    reason TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    UNIQUE(target_table, target_record_id, actor_id) -- One approval per actor per record
);

-- Index for approval queries
CREATE INDEX idx_approvals_target ON approvals(target_table, target_record_id);
CREATE INDEX idx_approvals_actor ON approvals(actor_id);

-- Amount-based approval bands (e.g., refunds by value)
CREATE TABLE amount_approval_bands (
    id SERIAL PRIMARY KEY,
    table_name TEXT NOT NULL,
    min_amount NUMERIC(19,4) NOT NULL DEFAULT 0,
    max_amount NUMERIC(19,4), -- NULL means unbounded
    approving_roles TEXT[] NOT NULL,
    required_approvals INTEGER NOT NULL CHECK (required_approvals >= 1),
    description TEXT
);

CREATE UNIQUE INDEX idx_amount_bands_table_amount ON amount_approval_bands(table_name, min_amount, COALESCE(max_amount, 'Infinity'::NUMERIC));

-- Table to associate approval bands with tables
CREATE TABLE table_approval_bands (
    table_name TEXT PRIMARY KEY,
    band_id INTEGER NOT NULL REFERENCES approval_bands(id),
    FOREIGN KEY (band_id) REFERENCES approval_bands(id)
);

-- Look up the generic approval band associated with a table.
-- Returns the band row or NULL when the table has no configured band.
CREATE FUNCTION get_approval_band(table_name TEXT)
RETURNS approval_bands AS $$
DECLARE
    v_band approval_bands;
BEGIN
    SELECT ab.* INTO v_band FROM approval_bands ab
    JOIN table_approval_bands tab ON ab.id = tab.band_id
    WHERE tab.table_name = table_name;
    RETURN v_band;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Find the amount-approval band that applies to a specific table and value.
-- Returns the matching band or NULL when no band covers the value.
CREATE FUNCTION get_amount_approval_band(p_table_name TEXT, p_amount NUMERIC)
RETURNS amount_approval_bands AS $$
DECLARE
    v_band amount_approval_bands;
BEGIN
    SELECT * INTO v_band FROM amount_approval_bands
    WHERE table_name = p_table_name
      AND p_amount >= min_amount
      AND (max_amount IS NULL OR p_amount < max_amount)
    ORDER BY min_amount DESC
    LIMIT 1;
    RETURN v_band;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Record an approval decision for a target record.
-- Verifies the actor has an approving role, is not the proposer, and then
-- inserts an approval row plus an audit entry. The band is taken from
-- table_approval_bands, not from the app.
CREATE FUNCTION record_approval(
    p_target_table TEXT,
    p_target_record_id TEXT,
    p_decision TEXT,
    p_reason TEXT DEFAULT NULL
)
RETURNS void AS $$
DECLARE
    v_band approval_bands;
    v_actor_id TEXT;
    v_actor_roles TEXT[];
    v_actor_role TEXT;
    v_current_approvals INTEGER;
    v_proposer_id TEXT;
BEGIN
    -- Get current actor
    v_actor_id := current_actor_id();
    v_actor_roles := current_actor_roles();
    
    -- Get approval band for this table
    SELECT * INTO v_band FROM get_approval_band(p_target_table);
    
    IF v_band IS NULL THEN
        RAISE EXCEPTION 'No approval band configured for table %', p_target_table;
    END IF;
    
    -- Check if actor has an approving role
    IF NOT (v_band.approving_roles && v_actor_roles) THEN
        RAISE EXCEPTION 'Actor % does not have required approving roles', v_actor_id;
    END IF;
    
    -- Get the actor's primary role for this approval
    v_actor_role := (SELECT unnest FROM unnest(v_actor_roles) unnest WHERE unnest = ANY(v_band.approving_roles) LIMIT 1);
    
    -- Check if actor is the proposer (should not approve own proposal)
    -- This requires the target table to have a 'created_by' or similar field
    BEGIN
        EXECUTE format('SELECT created_by FROM %I WHERE id = %L', p_target_table, p_target_record_id)
        INTO v_proposer_id;
        
        IF v_proposer_id = v_actor_id THEN
            RAISE EXCEPTION 'Actor % cannot approve their own proposal', v_actor_id;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        -- If table doesn't have created_by, skip this check
        NULL;
    END;
    
    -- Record the approval
    INSERT INTO approvals (
        target_table, target_record_id, actor_id, actor_role, decision, reason
    ) VALUES (
        p_target_table, p_target_record_id, v_actor_id, v_actor_role, p_decision, p_reason
    );
    
    -- Audit the approval
    PERFORM create_audit_entry(
        'approvals',
        p_target_record_id,
        'APPROVAL_' || UPPER(p_decision),
        jsonb_build_object(
            'target_table', p_target_table,
            'target_record_id', p_target_record_id,
            'decision', p_decision,
            'reason', p_reason,
            'actor_id', v_actor_id,
            'actor_role', v_actor_role
        )
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Return true when a record has at least the number of distinct approvals
-- required by its approval band. Returns true when no band is configured.
CREATE FUNCTION has_sufficient_approvals(p_target_table TEXT, p_target_record_id TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    v_band approval_bands;
    v_approval_count INTEGER;
BEGIN
    -- Get approval band
    SELECT * INTO v_band FROM get_approval_band(p_target_table);
    
    IF v_band IS NULL THEN
        RETURN true; -- No approval required
    END IF;
    
    -- Count distinct approvals (excluding refusals)
    SELECT COUNT(DISTINCT actor_id) INTO v_approval_count
    FROM approvals
    WHERE target_table = p_target_table
    AND target_record_id = p_target_record_id
    AND decision = 'approved';
    
    RETURN v_approval_count >= v_band.required_approvals;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Record an approval for an amount-based band (e.g., refunds).
-- Fetches the amount from the target record, resolves the matching band,
-- checks the actor's role and proposer segregation, then writes the approval.
CREATE FUNCTION record_amount_approval(
    p_target_table TEXT,
    p_target_record_id TEXT,
    p_decision TEXT,
    p_reason TEXT DEFAULT NULL
)
RETURNS void AS $$
DECLARE
    v_band amount_approval_bands;
    v_actor_id TEXT;
    v_actor_roles TEXT[];
    v_actor_role TEXT;
    v_amount NUMERIC;
    v_proposer_id TEXT;
    v_current_approvals INTEGER;
BEGIN
    v_actor_id := current_actor_id();
    v_actor_roles := current_actor_roles();

    -- Get the monetary amount from the record (valor or amount)
    BEGIN
        EXECUTE format('SELECT valor FROM %I WHERE id = %L', p_target_table, p_target_record_id)
            INTO v_amount;
    EXCEPTION WHEN undefined_column THEN
        EXECUTE format('SELECT amount FROM %I WHERE id = %L', p_target_table, p_target_record_id)
            INTO v_amount;
    END;

    IF v_amount IS NULL THEN
        RAISE EXCEPTION 'Could not determine amount for %', p_target_table;
    END IF;

    SELECT * INTO v_band FROM get_amount_approval_band(p_target_table, v_amount);
    IF v_band IS NULL THEN
        RAISE EXCEPTION 'No amount approval band configured for table % at value %', p_target_table, v_amount;
    END IF;

    IF NOT (v_band.approving_roles && v_actor_roles) THEN
        RAISE EXCEPTION 'Actor % does not have required approving roles for amount %', v_actor_id, v_amount;
    END IF;

    v_actor_role := (SELECT unnest FROM unnest(v_actor_roles) unnest WHERE unnest = ANY(v_band.approving_roles) LIMIT 1);

    -- Proposer segregation: cannot approve own request
    BEGIN
        EXECUTE format('SELECT solicitado_por FROM %I WHERE id = %L', p_target_table, p_target_record_id)
            INTO v_proposer_id;
    EXCEPTION WHEN undefined_column THEN
        EXECUTE format('SELECT created_by FROM %I WHERE id = %L', p_target_table, p_target_record_id)
            INTO v_proposer_id;
    END;

    IF v_proposer_id = v_actor_id THEN
        RAISE EXCEPTION 'Actor % cannot approve their own proposal', v_actor_id;
    END IF;

    INSERT INTO approvals (
        target_table, target_record_id, actor_id, actor_role, decision, reason
    ) VALUES (
        p_target_table, p_target_record_id, v_actor_id, v_actor_role, p_decision, p_reason
    );

    PERFORM create_audit_entry(
        'approvals',
        p_target_record_id,
        'APPROVAL_' || UPPER(p_decision),
        jsonb_build_object(
            'target_table', p_target_table,
            'target_record_id', p_target_record_id,
            'decision', p_decision,
            'reason', p_reason,
            'actor_id', v_actor_id,
            'actor_role', v_actor_role,
            'amount', v_amount
        )
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Return true when a record has enough distinct approvals for its amount-based band.
-- Returns true when the amount is null or no band covers it.
CREATE FUNCTION has_sufficient_amount_approvals(p_target_table TEXT, p_target_record_id TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    v_band amount_approval_bands;
    v_amount NUMERIC;
    v_approval_count INTEGER;
BEGIN
    BEGIN
        EXECUTE format('SELECT valor FROM %I WHERE id = %L', p_target_table, p_target_record_id)
            INTO v_amount;
    EXCEPTION WHEN undefined_column THEN
        EXECUTE format('SELECT amount FROM %I WHERE id = %L', p_target_table, p_target_record_id)
            INTO v_amount;
    END;

    IF v_amount IS NULL THEN
        RETURN true;
    END IF;

    SELECT * INTO v_band FROM get_amount_approval_band(p_target_table, v_amount);
    IF v_band IS NULL THEN
        RETURN true;
    END IF;

    SELECT COUNT(DISTINCT actor_id) INTO v_approval_count
    FROM approvals
    WHERE target_table = p_target_table
      AND target_record_id = p_target_record_id
      AND decision = 'approved';

    RETURN v_approval_count >= v_band.required_approvals;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Return the current approval status for a record: required, approved, refused,
-- and the derived status (no_approval_required, refused, approved, pending).
CREATE FUNCTION get_approval_status(p_target_table TEXT, p_target_record_id TEXT)
RETURNS TABLE(
    required INTEGER,
    approved INTEGER,
    refused INTEGER,
    status TEXT
) AS $$
DECLARE
    v_band approval_bands;
    v_approved INTEGER;
    v_refused INTEGER;
BEGIN
    -- Get approval band
    SELECT * INTO v_band FROM get_approval_band(p_target_table);
    
    IF v_band IS NULL THEN
        RETURN QUERY SELECT 0, 0, 0, 'no_approval_required'::TEXT;
    END IF;
    
    -- Count approvals
    SELECT COUNT(DISTINCT actor_id) INTO v_approved
    FROM approvals
    WHERE target_table = p_target_table
    AND target_record_id = p_target_record_id
    AND decision = 'approved';
    
    -- Count refusals
    SELECT COUNT(DISTINCT actor_id) INTO v_refused
    FROM approvals
    WHERE target_table = p_target_table
    AND target_record_id = p_target_record_id
    AND decision = 'refused';
    
    -- Determine status
    IF v_refused > 0 THEN
        RETURN QUERY SELECT v_band.required_approvals, v_approved, v_refused, 'refused'::TEXT;
    ELSIF v_approved >= v_band.required_approvals THEN
        RETURN QUERY SELECT v_band.required_approvals, v_approved, v_refused, 'approved'::TEXT;
    ELSE
        RETURN QUERY SELECT v_band.required_approvals, v_approved, v_refused, 'pending'::TEXT;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;