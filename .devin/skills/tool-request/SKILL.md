# tool-request

## When to use

Use this skill when an issue with the label `tool-request` is opened in the repository. The issue is expected to be written in non-engineer language, usually describing a new internal tool or queue.

## What to do

1. Read the issue body and title.
2. Read `AGENTS.md` and `MEASUREMENT.md` for the working agreement and session format.
3. Read the relevant legacy app in `legacy/` if the request maps to an existing Power App.
4. Create a new app directory under `apps/<issue-name>/` with:
   - `app.yaml` — entities, fields, PII flags, deadlines, RLS policies, business rules, UI requirements
   - `schema.sql` — tables, indexes, RLS, triggers, soft-delete and approval wiring
   - `seed-data.sql` — synthetic data with the right teams and roles
5. Load `schema.sql` and `seed-data.sql` into the running PostgreSQL container.
6. Run `npm run check`.
7. Open a pull request. The PR body must contain:
   - the original request, quoted
   - a requirement-to-implementation table
   - one line naming anything in the request that could not be expressed in the schema

## Naming rules

- Use full domain words: `reviewer`, `supervisor`, `qualificationDeadline`, `riskLevel`.
- Never `analyst1`, `user2`, `temp`, `data`, `foo`.
- Synthetic data only, with deliberately invalid document numbers.
- Use the design system in `design/`.

## Constraints

- Every read and write goes through the audit path in `core/`.
- RLS must be enabled and forced.
- The application role must have `NOBYPASSRLS` and no DDL rights.
- A rule must be declared once. Duplication is a kernel defect, not an app detail.
