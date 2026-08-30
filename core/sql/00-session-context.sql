-- Session context management
-- Every database operation runs within a transaction with actor context
-- Releasing the connection must not leak the actor into the next request

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Transaction-local settings for actor context.
-- Stores actor identity in GUC variables that live only for the current transaction.
-- Values are opaque strings: RLS policies and helper functions read them back with
-- exact-match comparisons. set_config is not dynamic SQL, so there is no injection
-- surface; the inputs are stored verbatim and never concatenated into a query.
CREATE FUNCTION set_actor_context(actor_id text, actor_roles text[], actor_team text)
RETURNS void AS $$
BEGIN
    PERFORM set_config('app.current_actor_id', COALESCE(actor_id, ''), true);
    PERFORM set_config('app.current_actor_roles', COALESCE(array_to_string(actor_roles, ','), ''), true);
    PERFORM set_config('app.current_actor_team', COALESCE(actor_team, ''), true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get current actor ID from transaction context.
-- Returns the value set by set_actor_context for this transaction, or empty string.
CREATE FUNCTION current_actor_id()
RETURNS text AS $$
BEGIN
    RETURN current_setting('app.current_actor_id', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get current actor roles from transaction context.
-- The comma-separated list stored by set_actor_context is converted back to a text array.
CREATE FUNCTION current_actor_roles()
RETURNS text[] AS $$
BEGIN
    RETURN string_to_array(current_setting('app.current_actor_roles', true), ',');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get current actor team from transaction context.
CREATE FUNCTION current_actor_team()
RETURNS text AS $$
BEGIN
    RETURN current_setting('app.current_actor_team', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Clear actor context.
-- Should be called before a pooled connection is reused, so the next request
-- does not inherit the previous actor's identity.
CREATE FUNCTION clear_actor_context()
RETURNS void AS $$
BEGIN
    PERFORM set_config('app.current_actor_id', '', true);
    PERFORM set_config('app.current_actor_roles', '', true);
    PERFORM set_config('app.current_actor_team', '', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Row-level security helper: check if actor has exact role match.
-- Role comparison is exact equality against the actor's role array.
CREATE FUNCTION has_role(expected_role text)
RETURNS boolean AS $$
BEGIN
    RETURN expected_role = ANY(current_actor_roles());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Row-level security helper: check if actor belongs to the expected team.
CREATE FUNCTION is_team_member(expected_team text)
RETURNS boolean AS $$
BEGIN
    RETURN current_actor_team() = expected_team;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;