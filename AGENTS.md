# Working agreement
An internal-tools factory for a regulated fintech, replacing a Power Apps estate.
The estate being replaced is in `legacy/`, unpacked from the .msapp files.
## Non-negotiable
1. Every read and write goes through the audit path in `core/`. Never write to
the database directly from an app.
2. Any read that feeds an authorisation decision runs inside the actor's session
context. A missing row is an error, never a default value.
3. Row-level security is ENABLED and FORCED on every table holding personal or
financial data. The application connects as a role with NOBYPASSRLS and no
DDL rights.
4. Roles are compared by exact match. Never by substring or regex.
5. Every retention period declares the rule it comes from.
6. A rule is declared once. If the same threshold, deadline or permission has to
be written in two places, that is a defect in the kernel, not a detail of the
app.
7. Never use real customer data. Synthetic only, with deliberately invalid
document numbers.
## Naming
Names are read by people. Use full domain words: `reviewer`, `supervisor`,
`qualificationDeadline`, `riskLevel`. Never `analyst1`, `user2`, `temp`, `data`,
`foo`. Seed data uses realistic Brazilian names, never placeholders.
## Design
`design/` holds the design system: tokens in `design/tokens/`, fonts in
`design/assets/fonts/`, and the guide in `design/BRAND-GUIDE.md`. The UI uses
those tokens and fonts. Do not invent a palette.
## Definition of done
- `npm run check` passes
- The PR body contains a requirement-to-implementation table

## Tool request trigger
When an issue is opened with the label `tool-request`:
1. Read the issue body with the full repository context (legacy, apps, kernel, design).
2. Translate the request into an app definition: `apps/<issue-name>/app.yaml`.
3. Generate `apps/<issue-name>/schema.sql` and `apps/<issue-name>/seed-data.sql`.
4. Load the schema, run `npm run check`, and open a pull request.
5. Include in the PR body: the original request quoted, the requirement-to-implementation table, and any requirement that could not be expressed in the schema.