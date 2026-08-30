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

### Session Log

| Sessão | Mensagens | ACUs | Tamanho | Commits no app | PR / merge | Sem retrabalho |
|---|---|---|---|---|---|---|
| 0 · Pré-cronômetro: repo, legacy, design, AGENTS, blueprint | [Session Insights] | — | M | 2 (`53ad14b`, `f2b2821`) | — | [ ] |
| 1 · Kernel + KYC from legacy | [Session Insights] | — | XL | 2 em `apps/kyc-review-queue` | PR #1 (`d3d9bf5`) | [ ] |
| 2 · Devoluções | [Session Insights] | — | M | 1 em `apps/refunds-dashboard` | PR #1 (`d3d9bf5`) | [ ] |
| 3 · Feature flags | [Session Insights] | — | S | 1 em `apps/feature-flag-admin` | PR #1 (`d3d9bf5`) | [ ] |
| 4 · Triagem de listas restritivas | [Session Insights] | — | L | 1 em `apps/restrictive-list-screening` | PR #2 (`9ed5435`) | [ ] |
| 5 · Intake (contestação de cartão) | [Session Insights] | — | M | 1 em `apps/dispute-review-queue` | PR #4 (`044fe10`) | [ ] |

**ACUs:** not captured from Devin Session Insights. The cells above are placeholders for future sessions. `Mensagens` and `Tamanho` also come from Session Insights.