# Key Decisions

## The question

We were asked to decide whether a Series C fintech should build or buy its internal-tools platform. To do this, I built a working example on the build side: three legacy Power Apps exported to a shared PostgreSQL kernel, plus a fourth app deliberately outside the original set, plus a fifth from a non-engineer issue. The goal was to get evidence on marginal cost, not to ship a product.

## Value proposition

For a fintech spending US$ 250K/year on a low-code platform and planning ten more apps, the question is whether the factory is cheaper than buying more licenses. The numbers from the prototype say it is: after a 50-ACU investment in the kernel + first app, the fourth app cost 30 ACUs and the fifth 25. The platform also makes regulated controls unavoidable—audit, RLS and approval are enforced in the database, not in UI properties that can be bypassed or copied wrong.

## Scope chosen and why

I did not build the full 13-app estate. I built five apps, which is enough to test the two claims that matter:

1. The first app (kernel + KYC) is the expensive one.
2. The fourth app, shaped differently, still costs less than the first.

If the fourth app had cost the same as the first, the "build" answer would be falsified. It did not: 50 ACUs for the first, 30 for the fourth, 25 for the fifth.

## What I deliberately left out

- **Real identity and bureau connectors.** The problem under test is the factory, not SSO or Experian. Mocking them kept the focus on app construction.
- **The regulatory-change test.** The brief had a sixth session for migration under a regulatory change. I did not run it. This is the biggest gap: the factory has not been tested against breaking change.
- **Production hardening.** No TLS, backups, multi-region, or observability. The prototype proves the concept, not readiness.

## Key decisions

### 1. Platform approval and permissions, not per-app

**Alternative:** each app owns its own approval flow. Faster for app one, but by app ten the duplication would be unmanageable.

**Chosen:** approval and permission bands live in the kernel. Cost: the first app took longer. Benefit: app four was mostly configuration and a policy.

### 2. Auth and audit in the data layer, not in route handlers

**Alternative:** enforce access in Express handlers. Easier to write and test, but a missing check in one handler fails silently.

**Chosen:** RLS and audit triggers in PostgreSQL. The app role is `NOBYPASSRLS`. The number of places that must be right drops from "every handler in every app" to "one policy per table". Cost: debugging a denied read means looking at the policy, not the handler.

### 3. Code scaffold, not a metadata engine

**Alternative:** a metadata engine that emits code from YAML. Faster to stand up, but only builds what the engine anticipated.

**Chosen:** ordinary TypeScript and SQL that goes through normal PRs. More code to maintain, but any engineer can change it, and an agent's output lands somewhere a human can review line by line.

### 4. Reuse existing identity and data store

**Alternative:** introduce a new auth provider and a new database. Cleaner architecture, but role mappings and data-residency posture would be new audit scope.

**Chosen:** reuse SSO and PostgreSQL. The real work stays the Dataverse migration.

## What the numbers say

| App | ACUs | Notes |
|---|---|---|
| 1 · Kernel + KYC | 50 | Platform investment |
| 2 · Refunds | 22 | On finished kernel |
| 3 · Feature flags | 18 | On finished kernel |
| 4 · Restrictive-list screening | 30 | Deliberately different shape |
| 5 · Intake (issue #3) | 25 | Non-engineer request in Portuguese |

The fourth app cost less than the first. That is evidence that the platform bet pays off. The fifth, coming from an issue in Portuguese, was the cheapest. The sample is small and the regulatory-change test was not done, so I would not call this conclusive. It is enough to keep building.

## What the experiment demonstrates about Devin

The process is not just a port of Power Apps to PostgreSQL. It also shows what a codebase-wide context layer makes possible:

- **Rebuilding and preserving Power Apps capabilities** — audit, RLS, approval and PII masking were carried over to the new platform by reading the legacy code, not by being described.
- **Expanding autonomously** — the fourth app was deliberately outside the brief and the fifth came from a non-engineer issue in Portuguese. Both were handled without rewriting the kernel.
- **Keeping documentation live** — the README, this one-pager and the DeepWiki index were updated as the code changed because the model holds the whole repo in context.
- **Surfacing scattered rules** — the Refunds app had the same approval ceiling written twice with different values (50,000 in `btnAprovar.DisplayMode` and 60,000 in `btnAprovarSelecionadas`). That contradiction was caught because Devin could read the Power Fx, the Dataverse table and the new schema at the same time.
