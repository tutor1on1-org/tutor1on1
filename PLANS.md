# PLANS
Last updated: 2026-07-24

## Current state
- Production and current clients use persisted zip-artifact manifest `state1/state2` as the only canonical sync parity contract, with the server copy authoritative for reset recovery.
- Teacher login blocks only on course/enrollment scaffolds and `student_kp` manifest metadata; student artifact payloads are materialized on demand when a teacher opens the relevant view.
- Student `Take server copy` wipes local learning/session/progress state before rebuilding it from canonical server artifacts, and a clean second login must transfer zero artifacts.
- Legacy cutover and backup repair preserve explicit progress and derive missing progress from durable session evidence before rebuilding canonical `student_kp` artifacts.

## Active roadmap
1. Keep artifact-sync, server-copy, release, and fresh-profile regression gates green.
2. Produce a signed and notarized macOS release before exposing any public macOS download.
