package handlers

import (
	"database/sql"
	"errors"
)

func getTeacherAccountID(db *sql.DB, userID int64) (int64, error) {
	row := db.QueryRow(
		"SELECT id FROM teacher_accounts WHERE user_id = ? AND status = 'active' LIMIT 1",
		userID,
	)
	var id int64
	if err := row.Scan(&id); err != nil {
		return 0, err
	}
	return id, nil
}

func isTeacherAccount(db *sql.DB, userID int64) (bool, int64, error) {
	id, err := getTeacherAccountID(db, userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return false, 0, nil
		}
		return false, 0, err
	}
	return true, id, nil
}

