# Changelog

All notable changes of `dlc-billing-db` are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow
[Semantic Versioning](https://semver.org/). A release is tagged `v<version>` once it is merged into `main`.

## [Unreleased]

## [3.0.0] - 2026-11-14

First release of `dlc-billing-db`.

### Added

- Add procedure prices schema and validity constraints.
- Add persistent idempotency records.
- Persist versioned additional price rules.
- Provision least-privilege runtime roles.
- Persist exact pre-invoice snapshots with scoped grants.
- Add invoice snapshots with read-only runtime grants.
- Protect draft allocation and finalization audit.
- Persist immutable invoice issuance and outbox intent.
- Track outbox publication separately from immutable events.
- Preserve payment history and enforce atomic invoice balances.
- Serialize manual charge admissions against encounter freeze.
- Store immutable minimized clinical source projections.
- Preserve manual charge facts and guarded encounter transitions.
- Restrict administrative price corrections to audited owner capability.

### Fixed

- Align fresh shared extension bootstrap with Appointments.
- Preserve justified historical manual prices during correction.
- Enforce financial boundaries and payment methods.
