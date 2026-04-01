# PLANS
Last updated: 2026-04-01

## Goal
Complete the zip-artifact sync cutover and remove the retired row-level session/progress/enrollment sync model from the product definition and runtime path.

## Phase 1: Canonical artifact model
1. Define and persist canonical artifact `state1/state2` on both server and client from the artifact manifest only.
2. Add stable `artifact_id`, byte `sha256`, and manifest mutation rules for upload, delete, and overwrite decisions.
3. Make sync read paths serve persisted manifest state instead of rescanning business rows or rebuilding folders on the hot path.

## Phase 2: Zip-only sync flow
1. Implement `state2 -> state1 -> changed artifact ids -> zip transfer -> parity verify` as the only canonical sync flow.
2. Add explicit download/upload conflict handling with `keep server`, `overwrite server with local`, and `defer`.
3. Keep local learning/session/progress state outside canonical server/client equality.

## Phase 3: Migration and cleanup
1. Take a verified production backup, run one server conversion to the artifact manifest, and bootstrap new clients from the authoritative server artifact set.
2. Remove retired row-level sync tables, endpoints, fallback hash logic, and compatibility branches after cutover.
3. Delete client-only services, background jobs, and tests that exist only for the retired row-level sync model.

## Phase 4: Validation and rollout
1. Validate first-login cutover, no-change second login, single-artifact upload/download, conflict decisions, and explicit delete behavior.
2. Run backup/restore drills and interrupted-rollout checks before production signoff.
3. Require post-deploy verification that a second real-account login transfers zero artifacts when nothing changed.
