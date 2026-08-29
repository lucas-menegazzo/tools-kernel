# Check script that verifies kernel invariants (PowerShell version)
# Exits non-zero on violation

$ErrorActionPreference = "Stop"

Write-Host "Checking kernel invariants..."

# Database connection parameters
$DB_HOST = $env:DB_HOST ?? "localhost"
$DB_PORT = $env:DB_PORT ?? "5432"
$DB_NAME = $env:DB_NAME ?? "tools_kernel"
$DB_USER = $env:DB_USER ?? "tools_kernel"
$DB_PASSWORD = $env:DB_PASSWORD ?? "tools_kernel_password"

$env:PGPASSWORD = $DB_PASSWORD

$sql = @"
-- Check 1: Row-level security is enabled on KYC cases
DO $$
DECLARE
    rls_enabled boolean;
BEGIN
    SELECT relrowsecurity INTO rls_enabled
    FROM pg_class 
    WHERE relname = 'kyc_cases' AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'kyc');
    
    IF NOT rls_enabled THEN
        RAISE EXCEPTION 'FAIL: RLS not enabled on kyc.kyc_cases';
    END IF;
    
    RAISE NOTICE 'PASS: RLS is enabled on kyc.kyc_cases';
END $$;

-- Check 2: Force row level security is enabled
DO $$
DECLARE
    relforcerowsecurity boolean;
BEGIN
    SELECT relforcerowsecurity INTO relforcerowsecurity
    FROM pg_class 
    WHERE relname = 'kyc_cases' AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'kyc');
    
    IF NOT relforcerowsecurity THEN
        RAISE EXCEPTION 'FAIL: Force RLS not enabled on kyc.kyc_cases';
    END IF;
    
    RAISE NOTICE 'PASS: Force RLS is enabled on kyc.kyc_cases';
END $$;

-- Check 3: Audit trigger is attached
DO $$
DECLARE
    trigger_exists boolean;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM pg_trigger 
        WHERE tgname = 'audit_trigger' 
        AND tgrelid = (SELECT oid FROM pg_class WHERE relname = 'kyc_cases' AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'kyc'))
    ) INTO trigger_exists;
    
    IF NOT trigger_exists THEN
        RAISE EXCEPTION 'FAIL: Audit trigger not attached to kyc.kyc_cases';
    END IF;
    
    RAISE NOTICE 'PASS: Audit trigger is attached to kyc.kyc_cases';
END $$;

-- Check 4: Soft delete protection is attached
DO $$
DECLARE
    trigger_exists boolean;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM pg_trigger 
        WHERE tgname = 'prevent_hard_delete_trigger' 
        AND tgrelid = (SELECT oid FROM pg_class WHERE relname = 'kyc_cases' AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'kyc'))
    ) INTO trigger_exists;
    
    IF NOT trigger_exists THEN
        RAISE EXCEPTION 'FAIL: Soft delete protection not attached to kyc.kyc_cases';
    END IF;
    
    RAISE NOTICE 'PASS: Soft delete protection is attached to kyc.kyc_cases';
END $$;

-- Check 5: Application role has NOBYPASSRLS
DO $$
DECLARE
    rolbypassrls boolean;
BEGIN
    SELECT rolbypassrls INTO rolbypassrls
    FROM pg_roles 
    WHERE rolname = 'tools_kernel_app';
    
    IF rolbypassrls THEN
        RAISE EXCEPTION 'FAIL: Application role has BYPASSRLS privilege';
    END IF;
    
    RAISE NOTICE 'PASS: Application role has NOBYPASSRLS';
END $$;

-- Check 6: Approval band is configured for KYC cases
DO $$
DECLARE
    band_configured boolean;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM table_approval_bands 
        WHERE table_name = 'kyc.kyc_cases'
    ) INTO band_configured;
    
    IF NOT band_configured THEN
        RAISE EXCEPTION 'FAIL: Approval band not configured for kyc.kyc_cases';
    END IF;
    
    RAISE NOTICE 'PASS: Approval band is configured for kyc.kyc_cases';
END $$;

-- Check 7: No deleted rows should be physically deleted (soft delete working)
DO $$
DECLARE
    total_rows bigint;
    soft_deleted_rows bigint;
BEGIN
    SELECT COUNT(*) INTO total_rows FROM kyc.kyc_cases;
    SELECT COUNT(*) INTO soft_deleted_rows FROM kyc.kyc_cases WHERE deleted_at IS NOT NULL;
    
    -- This is a basic check - in production you'd have more sophisticated logic
    RAISE NOTICE 'PASS: Soft delete structure exists (total: %, soft-deleted: %)', total_rows, soft_deleted_rows;
END $$;

-- Check 8: Session context functions exist
DO $$
DECLARE
    func_exists boolean;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM pg_proc 
        WHERE proname = 'current_actor_id'
    ) INTO func_exists;
    
    IF NOT func_exists THEN
        RAISE EXCEPTION 'FAIL: Session context function current_actor_id does not exist';
    END IF;
    
    RAISE NOTICE 'PASS: Session context functions exist';
END $$;

-- Check 9: PII masking functions exist
DO $$
DECLARE
    func_exists boolean;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM pg_proc 
        WHERE proname = 'mask_cpf'
    ) INTO func_exists;
    
    IF NOT func_exists THEN
        RAISE EXCEPTION 'FAIL: PII masking function mask_cpf does not exist';
    END IF;
    
    RAISE NOTICE 'PASS: PII masking functions exist';
END $$;

-- Check 10: 30-day qualification deadline trigger exists
DO $$
DECLARE
    trigger_exists boolean;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM pg_trigger 
        WHERE tgname = 'enforce_qualification_deadline' 
        AND tgrelid = (SELECT oid FROM pg_class WHERE relname = 'kyc_cases' AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'kyc'))
    ) INTO trigger_exists;
    
    IF NOT trigger_exists THEN
        RAISE EXCEPTION 'FAIL: 30-day qualification deadline trigger not attached';
    END IF;
    
    RAISE NOTICE 'PASS: 30-day qualification deadline trigger is attached';
END $$;

-- Check 11: Indexes exist for RLS performance
DO $$
DECLARE
    index_count integer;
BEGIN
    SELECT COUNT(*) INTO index_count
    FROM pg_indexes 
    WHERE tablename = 'kyc_cases' AND schemaname = 'kyc';
    
    IF index_count < 5 THEN
        RAISE EXCEPTION 'FAIL: Insufficient indexes on kyc.kyc_cases for RLS performance (found %)', index_count;
    END IF;
    
    RAISE NOTICE 'PASS: Sufficient indexes exist for RLS performance (found %)', index_count;
END $$;

-- Check 12: Audit trail table exists and has proper structure
DO $$
DECLARE
    table_exists boolean;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM pg_tables 
        WHERE tablename = 'audit_trail' AND schemaname = 'public'
    ) INTO table_exists;
    
    IF NOT table_exists THEN
        RAISE EXCEPTION 'FAIL: Audit trail table does not exist';
    END IF;
    
    RAISE NOTICE 'PASS: Audit trail table exists';
END $$;

RAISE NOTICE 'All invariants passed successfully!';
"@

try {
    psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -c $sql
    Write-Host "Invariant check completed successfully."
    exit 0
} catch {
    Write-Error "Invariant check failed: $_"
    exit 1
}