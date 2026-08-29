const { Pool } = require('pg');

// Database connection parameters
// Uses the application role which has NOBYPASSRLS and RLS will be enforced
const config = {
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 5434,
  database: process.env.DB_NAME || 'tools_kernel',
  user: process.env.DB_USER || 'tools_kernel_app',
  password: process.env.DB_PASSWORD || 'tools_kernel_app_password',
};

const pool = new Pool(config);

const checks = [
  {
    name: 'RLS enabled on kyc.kyc_cases',
    sql: `
      SELECT relrowsecurity 
      FROM pg_class 
      WHERE relname = 'kyc_cases' AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'kyc')
    `,
    validate: (result) => result.rows[0]?.relrowsecurity === true,
  },
  {
    name: 'Force RLS enabled on kyc.kyc_cases',
    sql: `
      SELECT relforcerowsecurity 
      FROM pg_class 
      WHERE relname = 'kyc_cases' AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'kyc')
    `,
    validate: (result) => result.rows[0]?.relforcerowsecurity === true,
  },
  {
    name: 'Audit trigger attached to kyc.kyc_cases',
    sql: `
      SELECT EXISTS (
        SELECT 1 FROM pg_trigger 
        WHERE tgname = 'audit_trigger' 
        AND tgrelid = (SELECT oid FROM pg_class WHERE relname = 'kyc_cases' AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'kyc'))
      )
    `,
    validate: (result) => result.rows[0]?.exists === true,
  },
  {
    name: 'Soft delete protection attached to kyc.kyc_cases',
    sql: `
      SELECT EXISTS (
        SELECT 1 FROM pg_trigger 
        WHERE tgname = 'prevent_hard_delete_trigger' 
        AND tgrelid = (SELECT oid FROM pg_class WHERE relname = 'kyc_cases' AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'kyc'))
      )
    `,
    validate: (result) => result.rows[0]?.exists === true,
  },
  {
    name: 'Application role has NOBYPASSRLS',
    sql: `
      SELECT rolbypassrls 
      FROM pg_roles 
      WHERE rolname = 'tools_kernel_app'
    `,
    validate: (result) => result.rows[0]?.rolbypassrls === false,
  },
  {
    name: 'Approval band configured for kyc.kyc_cases',
    sql: `
      SELECT EXISTS (
        SELECT 1 FROM table_approval_bands 
        WHERE table_name = 'kyc.kyc_cases'
      )
    `,
    validate: (result) => result.rows[0]?.exists === true,
  },
  {
    name: 'Session context function current_actor_id exists',
    sql: `
      SELECT EXISTS (
        SELECT 1 FROM pg_proc 
        WHERE proname = 'current_actor_id'
      )
    `,
    validate: (result) => result.rows[0]?.exists === true,
  },
  {
    name: 'PII masking function mask_cpf exists',
    sql: `
      SELECT EXISTS (
        SELECT 1 FROM pg_proc 
        WHERE proname = 'mask_cpf'
      )
    `,
    validate: (result) => result.rows[0]?.exists === true,
  },
  {
    name: '30-day qualification deadline trigger attached',
    sql: `
      SELECT EXISTS (
        SELECT 1 FROM pg_trigger 
        WHERE tgname = 'enforce_qualification_deadline' 
        AND tgrelid = (SELECT oid FROM pg_class WHERE relname = 'kyc_cases' AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'kyc'))
      )
    `,
    validate: (result) => result.rows[0]?.exists === true,
  },
  {
    name: 'Sufficient indexes for RLS performance',
    sql: `
      SELECT COUNT(*) 
      FROM pg_indexes 
      WHERE tablename = 'kyc_cases' AND schemaname = 'kyc'
    `,
    validate: (result) => parseInt(result.rows[0]?.count) >= 5,
  },
  {
    name: 'Audit trail table exists',
    sql: `
      SELECT EXISTS (
        SELECT 1 FROM pg_tables 
        WHERE tablename = 'audit_trail' AND schemaname = 'public'
      )
    `,
    validate: (result) => result.rows[0]?.exists === true,
  },
];

async function runChecks() {
  console.log('Checking kernel invariants...');
  
  let passed = 0;
  let failed = 0;
  
  for (const check of checks) {
    try {
      const result = await pool.query(check.sql);
      if (check.validate(result)) {
        console.log(`✓ PASS: ${check.name}`);
        passed++;
      } else {
        console.error(`✗ FAIL: ${check.name}`);
        failed++;
      }
    } catch (error) {
      console.error(`✗ ERROR: ${check.name} - ${error.message}`);
      failed++;
    }
  }
  
  await pool.end();
  
  console.log(`\n${passed} checks passed, ${failed} checks failed`);
  
  if (failed > 0) {
    process.exit(1);
  }
  
  console.log('All invariants passed successfully!');
  process.exit(0);
}

runChecks().catch(error => {
  console.error('Fatal error running checks:', error);
  process.exit(1);
});