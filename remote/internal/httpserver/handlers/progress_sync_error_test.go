package handlers

import (
	"errors"
	"testing"

	mysqlDriver "github.com/go-sql-driver/mysql"
	"github.com/gofiber/fiber/v2"
)

func TestClassifyProgressSyncSaveError_DataTooLarge(t *testing.T) {
	status, message := classifyProgressSyncSaveError(
		&mysqlDriver.MySQLError{Number: 1406},
	)
	if status != fiber.StatusBadRequest {
		t.Fatalf("status = %d, want %d", status, fiber.StatusBadRequest)
	}
	if message != "progress sync payload too large" {
		t.Fatalf("message = %q, want %q", message, "progress sync payload too large")
	}
}

func TestClassifyProgressSyncSaveError_InvalidPayload(t *testing.T) {
	status, message := classifyProgressSyncSaveError(
		&mysqlDriver.MySQLError{Number: 1366},
	)
	if status != fiber.StatusBadRequest {
		t.Fatalf("status = %d, want %d", status, fiber.StatusBadRequest)
	}
	if message != "progress sync payload invalid" {
		t.Fatalf("message = %q, want %q", message, "progress sync payload invalid")
	}
}

func TestClassifyProgressSyncSaveError_Default(t *testing.T) {
	status, message := classifyProgressSyncSaveError(errors.New("db unavailable"))
	if status != fiber.StatusInternalServerError {
		t.Fatalf("status = %d, want %d", status, fiber.StatusInternalServerError)
	}
	if message != "progress sync save failed" {
		t.Fatalf("message = %q, want %q", message, "progress sync save failed")
	}
}
