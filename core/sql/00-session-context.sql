-- Session context management
-- Every database operation runs within a transaction with actor context
-- Releasing the connection must not leak the actor into the next request

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Transaction-local settings for actor context
CREATE FUNCTION set_actor_context(actor_id text, actor_roles text[], actor_team text)
RETURNS void AS $$
BEGIN
    PERFORM set_config('app.current_actor_id', actor_id, true);
    PERFORM set_config('app.current_actor_roles', array_to_string(actor_roles, ','), true);
    PERFORM set_config('app.current_actor_team', actor_team, true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get current actor ID from transaction context
CREATE FUNCTION current_actor_id()
RETURNS text AS $$
BEGIN
    RETURN current_setting('app.current_actor_id', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get current actor roles from transaction context
CREATE FUNCTION current_actor_roles()
RETURNS text[] AS $$
BEGIN
    RETURN string_to_array(current_setting('app.current_actor_roles', true), ',');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get current actor team from transaction context
CREATE FUNCTION current_actor_team()
RETURNS text AS $$
BEGIN
    RETURN current_setting('app.current_actor_team', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Clear actor context (should be called when releasing connection)
CREATE FUNCTION clear_actor_context()
RETURNS void AS $$
BEGIN
    PERFORM set_config('app.current_actor_id', '', true);
    PERFORM set_config('app.current_actor_roles', '', true);
    PERFORM set_config('app.current_actor_team', '', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Row-level security helper: check if actor has exact role match
CREATE FUNCTION has_role(expected_role text)
RETURNS boolean AS $$
BEGIN
    RETURN expected_role = ANY(current_actor_roles());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Row-level security helper: check if actor is member of team
CREATE FUNCTION is_team_member(expected_team text)
RETURNS boolean AS $$
BEGIN
    RETURN current_actor_team() = expected_team;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;