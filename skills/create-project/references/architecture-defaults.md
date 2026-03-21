# Architecture Defaults

These defaults come from production experience. They're recommendations, not mandates.
Every decision here can be overridden by the user. When applying a default, briefly explain
the rationale so the user can make an informed choice.

---

## When to Apply Defaults

Apply when the user says "recommend", "you choose", "whatever you think is best", or leaves
a question blank. Always present defaults as a summary table and get confirmation before
proceeding.

---

## Application Architecture

| Decision | Default | Why | When to choose differently |
|----------|---------|-----|---------------------------|
| Architecture pattern | Modular Monolith | One deploy, in-process communication (microsecond latency), low ops overhead. Module boundaries are already defined — extracting to microservices later is straightforward. | Team > 10 engineers, or independent scaling requirements per module |
| Architecture style | Clean Architecture (3 layers) | Domain at center (zero external imports), Application in middle (use cases + DTOs), Infrastructure at outer (routes, repos, SDKs). Dependencies point only inward. | Simple CRUD with no business logic — skip domain layer |
| Dependency Injection | Manual bootstrap | Zero magic, all wiring explicit and IDE-traceable. `overrides` parameter for test injection. No decorators, no reflect-metadata. | Team already using InversifyJS or tsyringe consistently |
| Inter-module communication | In-process EventBus | Microsecond latency, `Promise.allSettled` for fault isolation. Same interface as SQS — swap when extracting to microservices. | Already need cross-service communication |

## Runtime & Language

| Technology | Default | Why | When to choose differently |
|------------|---------|-----|---------------------------|
| Language | TypeScript 5.7+ | Strong typing, mature ecosystem. `strict: true` mandatory. | Team has deep expertise in Go/Rust/Python for the problem domain |
| Runtime | Node.js 22+ | LTS, native ESM, `--env-file`, performance improvements. | CPU-bound workloads needing native performance |
| Package manager | pnpm 9.15+ | 2-3x faster than npm, hard links (disk savings), deterministic lockfile. | Already using yarn with PnP successfully |

## Web Framework

| Technology | Default | Why | When to choose differently |
|------------|---------|-----|---------------------------|
| Framework | Hono | Ultrafast, typed, composable middleware, zero deps. Works on Node, Deno, Bun, Workers. | Need extensive middleware ecosystem (Express), high-throughput with schema validation (Fastify) |
| Validation | @hono/zod-validator + Zod | Request validation with type inference. Schema = source of truth for TS types. | Already using Joi/class-validator across the org |

## Database

| Technology | Default | Why | When to choose differently |
|------------|---------|-----|---------------------------|
| Database | DynamoDB | Serverless, pay-per-request, auto-scaling, zero ops. Natural tenant isolation via partition key. | Complex relational queries, need JOINs, financial transactions needing strong ACID |
| ORM | ElectroDB | Abstracts PK/SK/GSI, generates optimized queries, validates schema. Single-table design without pain. | Using PostgreSQL or MongoDB |
| Design | Single Table | One table for all data. Maximum performance (one round-trip), minimum cost. GSIs for alternative access patterns. | Very different access pattern families that don't share entity relationships |

## Cache, Queues & Auth

| Technology | Default | Why |
|------------|---------|-----|
| Cache | Redis (ioredis) | Rate limiting, caching, session state. In-memory fallback when Redis down (fail-closed). |
| Queues | SQS | Async processing, DLQ for failed messages, long-polling (20s). |
| JWT | jose | JWKS support, all algorithms. More secure than jsonwebtoken (historical CVEs). |
| Encryption | KMS + AES-256-GCM | Envelope encryption. Plaintext DEK never stored. Industry standard. |

## Observability & Testing

| Technology | Default | Why |
|------------|---------|-----|
| Logger | Pino | Structured JSON, 5x faster than Winston. pino-pretty for dev. |
| AI tracing | Langfuse (optional) | LLM call tracing. Noop fallback when not configured. |
| Test runner | Vitest | 10x faster than Jest, native ESM, compatible with Jest API. |
| LLM eval | PromptFoo | Prompt quality evaluation. YAML-based, CI-friendly. |

## Infrastructure

| Technology | Default | Why |
|------------|---------|-----|
| IaC | AWS CDK | TypeScript — same language as app. Superior DX. |
| Local dev | LocalStack | Local AWS (DynamoDB, SQS, KMS, STS). Zero cost. |
| Container | Docker (multi-stage) | Alpine image, non-root user, prod deps only. ~150MB. |
| CI/CD | GitHub Actions | Lint + typecheck + unit + integration + build. CDK diff on PRs. |

## Security Defaults

| Control | Default implementation |
|---------|----------------------|
| Input validation | Zod schema on ALL routes |
| CORS | Explicit origin whitelist (never `*`) |
| Rate limiting | Per-tenant, fail-closed (in-memory fallback) |
| Webhook auth | HMAC-SHA256 with timing-safe comparison |
| Error masking | Generic 500 for internal errors |
| Secrets | Environment variables + Secrets Manager |
| Type safety | Branded types (TenantId, UserId) — compile-time confused deputy prevention |
| Audit trail | Hash chain (SHA256) |
| Token storage | KMS envelope encryption (AES-256-GCM) |
| Multi-tenancy | Partition key isolation — DynamoDB guarantees separation |

## TypeScript Config Defaults

```json
{
  "compilerOptions": {
    "target": "ESNext",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "verbatimModuleSyntax": true,
    "isolatedModules": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "paths": {
      "@/*": ["./src/*"],
      "@shared/*": ["./src/shared/*"],
      "@modules/*": ["./src/modules/*"]
    }
  }
}
```

## Code Conventions

- Entities are interfaces, NEVER classes (pure, serializable, no hidden behavior)
- Value Objects are branded types (compile-time safety, zero runtime cost)
- Timestamps are ISO 8601 strings (not Date objects, not epoch numbers)
- Imports use path aliases (`@/`, `@shared/`, `@modules/`)
- `.js` extension in imports (mandatory with ESM)
- `type` imports for types (enforced by ESLint `consistent-type-imports`)
- File naming: `{name}.entity.ts`, `{action}-{entity}.usecase.ts`, `{module}.routes.ts`

## Testing Pyramid Defaults

```
Level 1: Unit Tests     — Pure logic, mocked I/O
Level 2: Integration    — Real DB/Cache/Queue via LocalStack
Level 3: E2E            — Full pipeline, server running
Level 4: Smoke          — Post-deploy health checks
Level 5: LLM Eval       — Prompt quality (if AI features)
```

## Directory Structure Template

```
project-root/
  src/
    main.ts                    # Entry point
    app.ts                     # Framework app factory + middleware + routes
    bootstrap.ts               # DI container
    lifecycle.ts               # Graceful shutdown
    shared/
      config/index.ts          # Validated env config
      domain/
        errors.ts              # Base error hierarchy
        value-objects.ts       # Branded types
        types.ts               # Shared enums/types
        events.ts              # EventBus + DomainEvent
      application/ports/       # Port interfaces
      infra/                   # Shared infrastructure
    modules/
      <module-name>/
        domain/                # Entities, ports, errors
        application/           # Use cases, DTOs
        infra/                 # Routes, repository impls
  tests/
    unit/                      # Mocked, pure logic
    integration/               # Real infra (LocalStack)
    e2e/                       # Full pipeline
    smoke/                     # Post-deploy
    eval/                      # LLM quality (if AI)
    helpers/                   # Test utilities
    fixtures/                  # Reusable test data
  infra/
    cdk/                       # AWS CDK stacks
    localstack/                # Dev init scripts
  docs/
    core-docs/                 # Numbered documentation
  .github/workflows/           # CI/CD
  docker-compose.yml
  Dockerfile
  package.json
  tsconfig.json
  vitest.config.ts
  CLAUDE.md
```

## Middleware Stack Order

```
1. Error Handler (global catch)
2. CORS (before auth — preflight needs no auth)
3. Request ID (X-Request-Id)
4. Auth Middleware (JWT validation)
5. Tenant Middleware (tenant guard)
6. Rate Limit Middleware (per-tenant — needs tenantId from auth)
7. Audit Middleware (POST/PATCH/DELETE only)
```
