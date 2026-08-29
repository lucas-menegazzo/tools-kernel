# Measurement definition, fixed before the first session
Primary metric, from Session Insights. No manual timing:
- user messages per session (every time I had to stop and intervene)
- ACUs per session
- session size (XS to XL)
Secondary, from git:
- commits authored by me vs by Devin
- whether the PR merged with no follow-up fix commit
Unit of comparison:
- session 1 is the platform investment: the kernel plus the first app,
derived from the legacy Power App. One-time cost.
- apps 2 and 3 are apps on a finished kernel, also derived from legacy
- app 4 is deliberately a different shape, to test whether the curve is real
or an artefact of every app looking alike

## Session Log

### Session 0: Repository Setup (2026-08-29)
**Type:** Setup / Session 0
**Work Completed:**
- Created tools-kernel repository and GitHub repo
- Copied legacy Power Apps estate (3 apps) to legacy/
- Copied design system materials to design/
- Created MEASUREMENT.md with measurement framework
- Created AGENTS.md with working agreement
- Added docker-compose.yml with PostgreSQL service
- Added package.json with basic project structure
- Generated and verified environment.yaml blueprint with DRS
- Added 4 knowledge triggers to environment.yaml

**Commits:**
- 53ad14b: Initial commit with legacy apps and design system
- f2b2821: Added docker-compose and package.json

**Environment.yaml Blueprint:**
- ID: snapshot-blueprint-353c24912e92401da81416eca1ec6801
- Final build: sbj-3d0db57d918345f690e4d4bcff4542e8 (success)

**Metrics (to be captured from Session Insights):**
- User messages: [to be logged]
- ACUs: [to be logged]
- Session size: [to be logged]