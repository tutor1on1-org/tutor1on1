# Tutor1on1 Remote (API)

MVP server for teacher hosting + student marketplace.

## Stack
- Go + Fiber
- MySQL (RDS)
- sqlc for typed queries
- OSS for bundles/assets (signed URLs)

## Setup (local)
1. Install Go (1.22+).
2. Install sqlc: `go install github.com/sqlc-dev/sqlc/cmd/sqlc@latest`
3. Create `.env` from `.env.example`.
4. Run migrations (tooling TBD).
5. Run sqlc: `sqlc generate`
6. Start server: `go run ./cmd/server`

## Notes
- This repo is intentionally minimal; most endpoints are stubs until Phase 2.
- All content bodies are E2EE; server stores only ciphertext + minimal metadata.
- JWT rotation supports a staged rollout: sign with `JWT_SECRET`, optionally verify legacy tokens via `JWT_PREVIOUS_SECRETS` (comma-separated).
- Set `APP_ENV=production` to enforce `RECOVERY_TOKEN_ECHO=false`.
