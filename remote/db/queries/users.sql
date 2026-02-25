-- name: CreateUser :execresult
INSERT INTO users (email, password_hash, status)
VALUES (?, ?, ?);

-- name: GetUserByEmail :one
SELECT * FROM users
WHERE email = ?
LIMIT 1;

-- name: GetUserByID :one
SELECT * FROM users
WHERE id = ?
LIMIT 1;
