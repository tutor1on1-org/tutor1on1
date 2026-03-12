package handlers

import (
	"database/sql"
	"errors"

	"golang.org/x/crypto/bcrypt"
)

const (
	defaultAdminUsername = "admin"
	defaultAdminEmail    = "admin@family-teacher.local"
	defaultAdminPassword = "dennis_yang_edu"
)

func EnsureDefaultAdmin(db *sql.DB) error {
	if db == nil {
		return errors.New("database required")
	}
	var existingID int64
	row := db.QueryRow(
		`SELECT aa.id
		 FROM admin_accounts aa
		 JOIN users u ON u.id = aa.user_id
		 WHERE u.username = ?
		 LIMIT 1`,
		defaultAdminUsername,
	)
	if err := row.Scan(&existingID); err == nil {
		return nil
	} else if !errors.Is(err, sql.ErrNoRows) {
		return err
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(defaultAdminPassword), bcrypt.DefaultCost)
	if err != nil {
		return err
	}

	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	var userID int64
	userRow := tx.QueryRow("SELECT id FROM users WHERE username = ? LIMIT 1", defaultAdminUsername)
	if scanErr := userRow.Scan(&userID); scanErr != nil {
		if !errors.Is(scanErr, sql.ErrNoRows) {
			err = scanErr
			return err
		}
		res, insertErr := tx.Exec(
			"INSERT INTO users (username, email, password_hash, status) VALUES (?, ?, ?, 'active')",
			defaultAdminUsername,
			defaultAdminEmail,
			string(hash),
		)
		if insertErr != nil {
			err = insertErr
			return err
		}
		userID, err = res.LastInsertId()
		if err != nil {
			return err
		}
	} else {
		if _, err = tx.Exec(
			"UPDATE users SET email = ?, password_hash = ?, status = 'active' WHERE id = ?",
			defaultAdminEmail,
			string(hash),
			userID,
		); err != nil {
			return err
		}
	}

	if _, err = tx.Exec(
		"INSERT IGNORE INTO admin_accounts (user_id) VALUES (?)",
		userID,
	); err != nil {
		return err
	}
	return tx.Commit()
}
