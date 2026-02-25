-- name: CreateUser :execresult
INSERT INTO users (username, email, password_hash, status)
VALUES (?, ?, ?, ?);

-- name: GetUserByUsername :one
SELECT * FROM users
WHERE username = ?
LIMIT 1;

-- name: GetUserByEmail :one
SELECT * FROM users
WHERE email = ?
LIMIT 1;

-- name: GetUserByID :one
SELECT * FROM users
WHERE id = ?
LIMIT 1;
