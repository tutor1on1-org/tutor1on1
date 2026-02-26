# PLANS
Last updated: 2026-02-26

## Goal
Stabilize and harden the teacher-managed marketplace + enrollment + bundle sync workflow for production usage.

## Phase 1: Reliability baseline
1. Add end-to-end regression scripts for teacher upload / student enroll / approve / student download.
2. Add API and client integration tests for enrollment gating and bundle version handling.
3. Add server preflight checks for storage permissions, body limits, and required env vars.

## Phase 2: Progress visibility
1. Improve teacher progress dashboard using synced student session text summaries.
2. Add filters by teacher course, student, and time range.
3. Add explicit sync state indicators (last sync time, pending uploads, retry status).

## Phase 3: Security and operations
1. Rotate temporary secrets and enforce production env profile.
2. Enable SMTP recovery production path and monitor delivery failures.
3. Add restore-tested backup runbook and incident checklist.

## Phase 4: Marketplace UX polish
1. Add course catalog search/filter/pagination.
2. Clarify enrollment status states and retry UX.
3. Add explicit handling for course/bundle re-download and prompt overwrite behavior.
