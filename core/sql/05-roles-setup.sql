-- Application role setup with NOBYPASSRLS
-- The application connects with a role that has NOBYPASSRLS and no DDL rights

-- Create application role with login capability
CREATE ROLE tools_kernel_app WITH LOGIN PASSWORD 'tools_kernel_app_password' NOBYPASSRLS;

-- Grant necessary permissions to application role
GRANT CONNECT ON DATABASE tools_kernel TO tools_kernel_app;
GRANT USAGE ON SCHEMA public TO tools_kernel_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO tools_kernel_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO tools_kernel_app;

-- Grant execute on kernel functions
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO tools_kernel_app;

-- Function to set up actor context (should be called by application layer)
CREATE FUNCTION app_set_actor_context(actor_id TEXT, actor_roles TEXT[], actor_team TEXT)
RETURNS void AS $$
BEGIN
    PERFORM set_actor_context(actor_id, actor_roles, actor_team);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute on context functions to application role
GRANT EXECUTE ON FUNCTION set_actor_context(TEXT, TEXT[], TEXT) TO tools_kernel_app;
GRANT EXECUTE ON FUNCTION current_actor_id() TO tools_kernel_app;
GRANT EXECUTE ON FUNCTION current_actor_roles() TO tools_kernel_app;
GRANT EXECUTE ON FUNCTION current_actor_team() TO tools_kernel_app;
GRANT EXECUTE ON FUNCTION clear_actor_context() TO tools_kernel_app;
GRANT EXECUTE ON FUNCTION has_role(TEXT) TO tools_kernel_app;
GRANT EXECUTE ON FUNCTION is_team_member(TEXT) TO tools_kernel_app;

-- Grant execute on audit functions to application role
GRANT EXECUTE ON FUNCTION create_audit_entry(TEXT, TEXT, TEXT, JSONB) TO tools_kernel_app;
GRANT EXECUTE ON FUNCTION attach_audit_trigger(TEXT) TO tools_kernel_app;

-- Grant execute on soft delete functions to application role
GRANT EXECUTE ON FUNCTION create_soft_delete_table(TEXT, INTEGER, TEXT) TO tools_kernel_app;
GRANT EXECUTE ON FUNCTION attach_soft_delete_protection(TEXT) TO tools_kernel_app;
GRANT EXECUTE ON FUNCTION soft_delete_record(TEXT, TEXT) TO tools_kernel_app;

-- Grant execute on PII masking functions to application role
GRANT EXECUTE ON FUNCTION mask_cpf(TEXT, BOOLEAN) TO tools_kernel_app;
GRANT EXECUTE ON FUNCTION mask_email(TEXT, BOOLEAN) TO tools_kernel_app;
GRANT EXECUTE ON FUNCTION mask_phone(TEXT, BOOLEAN) TO tools_kernel_app;
GRANT EXECUTE ON FUNCTION can_reveal_pii() TO tools_kernel_app;
GRANT EXECUTE ON FUNCTION mask_pii(TEXT, TEXT) TO tools_kernel_app;

-- Grant execute on approval functions to application role
GRANT EXECUTE ON FUNCTION record_approval(TEXT, TEXT, TEXT, TEXT) TO tools_kernel_app;
GRANT EXECUTE ON FUNCTION has_sufficient_approvals(TEXT, TEXT) TO tools_kernel_app;
GRANT EXECUTE ON FUNCTION get_approval_status(TEXT, TEXT) TO tools_kernel_app;
GRANT EXECUTE ON FUNCTION record_amount_approval(TEXT, TEXT, TEXT, TEXT) TO tools_kernel_app;
GRANT EXECUTE ON FUNCTION has_sufficient_amount_approvals(TEXT, TEXT) TO tools_kernel_app;
GRANT EXECUTE ON FUNCTION get_amount_approval_band(TEXT, NUMERIC) TO tools_kernel_app;
GRANT SELECT ON amount_approval_bands TO tools_kernel_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO tools_kernel_app;

-- Ensure future functions are also executable by app role
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO tools_kernel_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE ON TABLES TO tools_kernel_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO tools_kernel_app;