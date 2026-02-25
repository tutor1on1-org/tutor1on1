-- name: CreateRefreshToken :execresult
INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
VALUES (?, ?, ?);

-- name: GetRefreshToken :one
SELECT * FROM refresh_tokens
WHERE token_hash = ?
LIMIT 1;

-- name: RevokeRefreshToken :exec
UPDATE refresh_tokens
SET revoked_at = NOW()
WHERE token_hash = ?;
