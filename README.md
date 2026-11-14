# DI LUCCA — Billing Database

Database migrations and schema definitions for the Billing bounded context of **DI LUCCA Dental Care & Technology**.

Developed as part of the Distributed Systems 2026-B project at CORHUILA.

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

Liquibase 4.31.1 validated and applied this migration on the isolated PostgreSQL 16 test database. Integration tests verified positive prices, allowed item types, valid versions, unique source/version pairs, rejection of overlapping validity, and acceptance of adjacent validity intervals. The database now has six applied changesets. These are local validation results, not deployment evidence.

### Pending Database Work

- Integrated QA validation of additional rule writes.
- Manual charges.
- Invoice persistence.
- Payment records.
- Integration with the Billing API.
- Additional database integrity and concurrency tests.

These components must follow the official DI LUCCA contracts and data model.

## Migration Validation

The initial procedure price migrations were validated using:

- PostgreSQL 16.
- Liquibase 4.31.1.
- An isolated Docker test environment.

Verified operations:

- Liquibase changelog validation.
- Successful execution of four changesets.
- PostgreSQL constraint creation.
- Rejection of overlapping active validity periods.
- Acceptance of adjacent validity periods.
- Confirmation that Liquibase reports no pending changes.

These validations were performed in a temporary test environment, not in production.

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
