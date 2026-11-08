# DI LUCCA — Billing Database

Database migrations and schema definitions for the Billing bounded context of **DI LUCCA Dental Care & Technology**.

Developed as part of the Distributed Systems 2026-B project at CORHUILA.

Publication scope and coordinated API/Portal acceptance: [2026-11-08 report](docs/publication-2026-11-08.md).

## Project Overview

This repository manages the PostgreSQL database structure owned by the DI LUCCA Billing microservice.

It contains version-controlled Liquibase migrations for database schemas, tables, constraints, indexes, and other database objects.

The Billing database supports procedure pricing, invoice management, manual charges, and payment records as defined in the official project documentation.

## Technology Stack

- PostgreSQL 16
- Liquibase
- YAML changelogs
- SQL
- Docker for isolated database testing

## Database Architecture

DI LUCCA uses a distributed architecture with separate bounded contexts:

- IAM
- Patients
- Appointments
- Clinical
- Billing

Billing owns the `billing` schema in PostgreSQL.

Database changes must respect the boundaries of the Billing service and must not introduce undocumented cross-service dependencies.

## Migration Structure

The repository organizes Liquibase migrations into the following directories:

```text
changelog/
  changelog-master.yaml

01_ddl/
  00_extensions/
  01_schemas/
  02_types/
  03_tables/
  04_alter/
  05_views/
  06_materialized_views/
  07_functions/
  08_procedures/
  09_triggers/
  10_indexes/

02_dml/
03_dcl/
04_tcl/
05_rollbacks/
```

The main changelog is located at:

`changelog/changelog-master.yaml`

Liquibase processes the included migration files according to their declared order.

## Implemented Database Migrations

### Procedure Price Catalog

The initial Billing database migrations include:

- PostgreSQL `btree_gist` extension.
- Creation of the `billing` schema.
- Creation of the `billing.procedure_prices` table.
- Positive exact monetary values using `NUMERIC(14,2)`.
- COP currency validation.
- Procedure price version uniqueness.
- Validity period validation.
- Active price validity exclusion constraints using GiST.
- Audit fields for price records.

The exclusion constraint prevents overlapping active validity periods for the same procedure.

Validity periods use start-inclusive and end-exclusive intervals.

### Additional Price Rules

The local `billing-006-create-additional-price-rules` migration adds `billing.additional_price_rules` with positive exact COP unit prices, the four contract item types, version uniqueness, audit fields, and a GiST exclusion constraint for active validity intervals. Historical approval metadata is retained; new API writes must use `requiresApproval: false`.

Liquibase 4.31.1 validated and applied this migration on the isolated PostgreSQL 16 test database. Integration tests verified positive prices, allowed item types, valid versions, unique source/version pairs, rejection of overlapping validity, and acceptance of adjacent validity intervals. That historical baseline contained six applied changesets. These are local validation results, not deployment evidence.

### Financial and integration storage

The changelog now includes:

- Immutable pre-invoice billable snapshots and encounter accounts (008/009).
- Invoice reads, draft allocation and appointment validations (010-013).
- Invoice issuance, immutable event snapshots and outbox delivery (014-017).
- Payment methods, locked payment registration and event-specific receipts (018/019).
- Encounter freeze gates and manual-write admissions (020/021).
- Clinical inbox deduplication and owner-local source projections (022/023).
- Manual charges with restricted audit writes (024/025).
- Audited administrative price corrections and legacy manual-price protection (026-028).
- Manual charge/source/snapshot consistency and payment/receipt invoice correlation (029).
- Default internal payment methods from the documented MVP, preserving existing configuration (030).
- Invoice financial boundaries and finite catalog prices, correcting audit A01-A03 (031).

See [API/Portal coverage](docs/contract-coverage.md) for implemented workflows,
configuration requirements and remaining acceptance work. Existing changesets
remain unchanged; additions are forward migrations.

The current local database and Docker container are named `dlc-billing-db`.
The legacy local test database was upgraded to 31 changesets with preserved
data/history and a verified pre-migration backup. See the
[local application and integration record](docs/local-application-and-integration-2026-11-07.md)
for the exact target, artifact inputs, executed scenarios and acceptance limits.

## Migration validation

Run the complete SQL regression suite against a fresh disposable PostgreSQL 16:

```powershell
python tests/run-isolated.py
```

Include upgrade from committed `HEAD` with historical data and a logical
backup/restore verification:

```powershell
python tests/run-isolated.py --upgrade --restore
```

With the sibling Billing API and cached Maven dependencies, verify its real JDBC
draft/issuance/payment/correction tests separately:

```powershell
python tests/run-isolated.py --api-only
```

Only `--api-only` publishes a random PostgreSQL port on `127.0.0.1`, using generated
temporary credentials. It rejects skipped API tests. No owner microservices are
started. See [audit corrections](docs/financial-boundary-corrections.md).

Requires Docker with access to `postgres:16-alpine` and
`liquibase/liquibase:4.31.1`. The runner uses a random database container and
network, publishes no ports, accepts no external database credentials, validates
and applies the real Liquibase changelog as `billing_migrator`, repeats the update,
and executes every `tests/*.sql` suite. Tests roll back their fixtures and exercise
`billing_runtime` permissions. The runner removes only its own Docker resources.

For shared-extension compatibility with the Appointments owner, see
[shared extension bootstrap](docs/shared-extension-bootstrap.md).

Local regression and logical restore results do not establish target deployment,
production RPO/RTO, cross-owner credentials/topology recovery or real
IAM/Gateway/Portal acceptance.

## Related Repositories

- [DI LUCCA Documentation](https://github.com/code-corhuila/dlc-docs)
- [Billing API](https://github.com/code-corhuila/dlc-billing-api)
- [Billing Portal](https://github.com/code-corhuila/dlc-billing-portal)
- [API Gateway](https://github.com/code-corhuila/dlc-api-gateway)
- [Infrastructure](https://github.com/code-corhuila/dlc-infra)

## Branching and Contributions

The project uses three permanent branches:

- `develop` — development integration.
- `qa` — quality assurance.
- `main` — release branch.

Changes are developed in short-lived branches and submitted through Pull Requests.

Contribution guidelines:

- Follow Conventional Commits.
- Keep Pull Requests within 400 changed lines.
- Validate migrations before requesting integration.
- Preserve existing data and avoid destructive changes.
- Use explicit and reviewed rollback procedures.
- Do not modify database objects owned by other bounded contexts.
- Follow the current DI LUCCA governance documentation.

## Documentation

Official project documentation:

https://github.com/code-corhuila/dlc-docs

Billing data model:

`09-microservices/services/06-billing-service/data-model.md`

Billing API contract:

`07-api/contracts/openapi/billing-service.yaml`

## Project

**DI LUCCA Dental Care & Technology**

CORHUILA — Systems Engineering

Distributed Systems — 2026-B
