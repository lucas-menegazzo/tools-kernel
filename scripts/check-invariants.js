const { Pool } = require('pg');

// Database connection parameters
// Uses the application role which has NOBYPASSRLS and RLS will be enforced
const config = {
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 5434,
  database: process.env.DB_NAME || 'tools_kernel',
  user: process.env.DB_USER || 'tools_kernel_app',
  password: process.env.DB_PASSWORD || 'tools_kernel_app_password',
  // Abort quickly if the database is not reachable.
  connectionTimeoutMillis: 5000,
};

const pool = new Pool(config);

// Log unexpected pool errors instead of crashing the process.
pool.on('error', (err) => {
  console.error('Unexpected database pool error:', err.message);
});

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
  {
    name: 'RLS enabled on refunds.devolucoes',
    sql: `
      SELECT relrowsecurity 
      FROM pg_class 
      WHERE relname = 'devolucoes' AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'refunds')
    `,
    validate: (result) => result.rows[0]?.relrowsecurity === true,
  },
  {
    name: 'Force RLS enabled on refunds.devolucoes',
    sql: `
      SELECT relforcerowsecurity 
      FROM pg_class 
      WHERE relname = 'devolucoes' AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'refunds')
    `,
    validate: (result) => result.rows[0]?.relforcerowsecurity === true,
  },
  {
    name: 'Refunds amount approval bands configured',
    sql: `
      SELECT COUNT(*) 
      FROM amount_approval_bands 
      WHERE table_name = 'refunds.devolucoes'
    `,
    validate: (result) => parseInt(result.rows[0]?.count) >= 3,
  },
  {
    name: 'Force RLS enabled on customer_refunds.refund_requests',
    sql: `
      SELECT relforcerowsecurity
      FROM pg_class
      WHERE relname = 'refund_requests' AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'customer_refunds')
    `,
    validate: (result) => result.rows[0]?.relforcerowsecurity === true,
  },
  {
    name: 'Audit trigger attached to customer_refunds.refund_requests',
    sql: `
      SELECT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'audit_trigger'
        AND tgrelid = (SELECT oid FROM pg_class WHERE relname = 'refund_requests' AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'customer_refunds'))
      )
    `,
    validate: (result) => result.rows[0]?.exists === true,
  },
  {
    name: 'Soft delete protection attached to customer_refunds.refund_requests',
    sql: `
      SELECT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'prevent_hard_delete_trigger'
        AND tgrelid = (SELECT oid FROM pg_class WHERE relname = 'refund_requests' AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'customer_refunds'))
      )
    `,
    validate: (result) => result.rows[0]?.exists === true,
  },
  {
    name: 'Customer refund request amount bands cover the three alcadas',
    sql: `
      SELECT COUNT(*)
      FROM amount_approval_bands
      WHERE table_name = 'customer_refunds.refund_requests'
    `,
    validate: (result) => parseInt(result.rows[0]?.count) === 3,
  },
  {
    name: '15-day resolution deadline trigger attached',
    sql: `
      SELECT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'enforce_resolution_deadline'
        AND tgrelid = (SELECT oid FROM pg_class WHERE relname = 'refund_requests' AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'customer_refunds'))
      )
    `,
    validate: (result) => result.rows[0]?.exists === true,
  },
  {
    name: 'Customer refund CPF masking gate exists',
    sql: `
      SELECT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'customer_refunds' AND p.proname = 'can_reveal_customer_cpf'
      )
    `,
    validate: (result) => result.rows[0]?.exists === true,
  },
  {
    name: 'Refunds approval shared code path function exists',
    sql: `
      SELECT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'refunds' AND p.proname = 'aprovar_devolucoes'
      )
    `,
    validate: (result) => result.rows[0]?.exists === true,
  },
];

async function runChecks() {
  console.log('Checking kernel invariants...');

  let passed = 0;
  let failed = 0;

  // Verify the database is reachable before running any invariant checks.
  try {
    const client = await pool.connect();
    await client.query('SELECT 1');
    client.release();
    console.log('Database connection verified');
  } catch (error) {
    console.error('Database connection failed:', error.message);
    throw error;
  }

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

  console.log(`\n${passed} checks passed, ${failed} checks failed`);

  if (failed > 0) {
    return 1;
  }

  console.log('All invariants passed successfully!');
  return 0;
}

async function main() {
  let exitCode = 1;
  try {
    exitCode = await runChecks();
  } catch (error) {
    console.error('Fatal error running checks:', error);
    exitCode = 1;
  } finally {
    await pool.end();
  }
  process.exit(exitCode);
}

main();