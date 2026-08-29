-- Database initialization script
-- This script is run when the PostgreSQL container is first created

-- Create database extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Note: For cross-platform compatibility, we need to read the SQL files 
-- and execute them directly. This is a placeholder - the actual implementation
-- would use a script to load these files.

-- Core SQL files that should be loaded:
-- 1. core/sql/00-session-context.sql
-- 2. core/sql/01-audit-trail.sql  
-- 3. core/sql/02-soft-delete.sql
-- 4. core/sql/03-pii-masking.sql
-- 5. core/sql/04-approval-system.sql
-- 6. core/sql/05-roles-setup.sql

-- KYC app files:
-- 7. apps/kyc-review-queue/schema.sql
-- 8. apps/kyc-review-queue/seed-data.sql

-- For now, we'll create a basic structure to test the setup
-- In production, use a proper migration tool