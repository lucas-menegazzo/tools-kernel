const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');

const dbConfig = {
  connectionTimeoutMillis: 10000,
};

if (process.env.DATABASE_URL) {
  dbConfig.connectionString = process.env.DATABASE_URL;
} else {
  dbConfig.host = process.env.DB_HOST || 'localhost';
  dbConfig.port = process.env.DB_PORT || 5434;
  dbConfig.database = process.env.DB_NAME || 'tools_kernel';
  dbConfig.user = process.env.DB_USER || 'tools_kernel_app';
  dbConfig.password = process.env.DB_PASSWORD || 'tools_kernel_app_password';
}

if (
  process.env.DB_SSL === 'true' ||
  process.env.DB_SSL === 'require' ||
  process.env.DB_SSL === 'railway'
) {
  dbConfig.ssl = { rejectUnauthorized: false };
  if (process.env.DB_SSL === 'railway' || process.env.DB_SSL_SERVERNAME) {
    dbConfig.ssl.servername = process.env.DB_SSL_SERVERNAME || 'localhost';
  }
}

const pool = new Pool(dbConfig);

const files = [
  'core/sql/00-session-context.sql',
  'core/sql/01-audit-trail.sql',
  'core/sql/02-soft-delete.sql',
  'core/sql/03-pii-masking.sql',
  'core/sql/04-approval-system.sql',
  'core/sql/05-roles-setup.sql',
  'apps/kyc-review-queue/schema.sql',
  'apps/kyc-review-queue/seed-data.sql',
  'apps/refunds-dashboard/schema.sql',
  'apps/refunds-dashboard/seed-data.sql',
  'apps/feature-flag-admin/schema.sql',
  'apps/feature-flag-admin/seed-data.sql',
];

async function run() {
  console.log('Creating pgcrypto extension...');
  await pool.query('CREATE EXTENSION IF NOT EXISTS pgcrypto;');

  for (const file of files) {
    const filePath = path.join(__dirname, '..', file);
    if (!fs.existsSync(filePath)) {
      console.log(`Skipping missing file: ${file}`);
      continue;
    }

    const sql = fs.readFileSync(filePath, 'utf8');
    if (!sql.trim()) {
      console.log(`Skipping empty file: ${file}`);
      continue;
    }

    console.log(`Loading ${file}...`);
    await pool.query(sql);
    console.log(`Loaded ${file}`);
  }

  console.log('Database seeded successfully.');
  await pool.end();
}

run().catch((error) => {
  console.error('Seeding failed:', error.message);
  if (error.cause) console.error('Cause:', error.cause);
  pool.end().finally(() => process.exit(1));
});
