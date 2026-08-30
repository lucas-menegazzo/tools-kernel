#!/bin/sh
# Database initialization script for PostgreSQL container
# This script loads all SQL files in the correct order

set -e

echo "Starting database initialization..."

# Create database extensions
echo "Creating extensions..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" << 'EOSQL'
    CREATE EXTENSION IF NOT EXISTS pgcrypto;
EOSQL

# Load core SQL files in order
echo "Loading core SQL files..."
if [ -f "/core/sql/00-session-context.sql" ]; then
    echo "Loading /core/sql/00-session-context.sql..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f /core/sql/00-session-context.sql
fi

if [ -f "/core/sql/01-audit-trail.sql" ]; then
    echo "Loading /core/sql/01-audit-trail.sql..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f /core/sql/01-audit-trail.sql
fi

if [ -f "/core/sql/02-soft-delete.sql" ]; then
    echo "Loading /core/sql/02-soft-delete.sql..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f /core/sql/02-soft-delete.sql
fi

if [ -f "/core/sql/03-pii-masking.sql" ]; then
    echo "Loading /core/sql/03-pii-masking.sql..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f /core/sql/03-pii-masking.sql
fi

if [ -f "/core/sql/04-approval-system.sql" ]; then
    echo "Loading /core/sql/04-approval-system.sql..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f /core/sql/04-approval-system.sql
fi

if [ -f "/core/sql/05-roles-setup.sql" ]; then
    echo "Loading /core/sql/05-roles-setup.sql..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f /core/sql/05-roles-setup.sql
fi

# Load KYC app SQL files
echo "Loading KYC app SQL files..."
if [ -f "/apps/kyc-review-queue/schema.sql" ]; then
    echo "Loading /apps/kyc-review-queue/schema.sql..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f /apps/kyc-review-queue/schema.sql
fi

if [ -f "/apps/kyc-review-queue/seed-data.sql" ]; then
    echo "Loading /apps/kyc-review-queue/seed-data.sql..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f /apps/kyc-review-queue/seed-data.sql
fi

# Load Refunds Dashboard app SQL files
echo "Loading Refunds Dashboard app SQL files..."
if [ -f "/apps/refunds-dashboard/schema.sql" ]; then
    echo "Loading /apps/refunds-dashboard/schema.sql..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f /apps/refunds-dashboard/schema.sql
fi

if [ -f "/apps/refunds-dashboard/seed-data.sql" ]; then
    echo "Loading /apps/refunds-dashboard/seed-data.sql..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f /apps/refunds-dashboard/seed-data.sql
fi

# Load Feature Flag Admin app SQL files
echo "Loading Feature Flag Admin app SQL files..."
if [ -f "/apps/feature-flag-admin/schema.sql" ]; then
    echo "Loading /apps/feature-flag-admin/schema.sql..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f /apps/feature-flag-admin/schema.sql
fi

if [ -f "/apps/feature-flag-admin/seed-data.sql" ]; then
    echo "Loading /apps/feature-flag-admin/seed-data.sql..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f /apps/feature-flag-admin/seed-data.sql
fi

# Load Customer Refund Requests app SQL files
echo "Loading Customer Refund Requests app SQL files..."
if [ -f "/apps/customer-refund-requests/schema.sql" ]; then
    echo "Loading /apps/customer-refund-requests/schema.sql..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f /apps/customer-refund-requests/schema.sql
fi

if [ -f "/apps/customer-refund-requests/seed-data.sql" ]; then
    echo "Loading /apps/customer-refund-requests/seed-data.sql..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f /apps/customer-refund-requests/seed-data.sql
fi

echo "Database initialization completed successfully."