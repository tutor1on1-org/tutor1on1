package handlers

import (
	"strconv"
	"strings"

	"github.com/gofiber/fiber/v2"
)

func parseLimitQuery(c *fiber.Ctx, defaultLimit int, maxLimit int) (int, error) {
	val := strings.TrimSpace(c.Query("limit"))
	if val == "" {
		return defaultLimit, nil
	}
	parsed, err := strconv.Atoi(val)
	if err != nil || parsed <= 0 {
		return 0, fiber.NewError(fiber.StatusBadRequest, "limit invalid")
	}
	if maxLimit > 0 && parsed > maxLimit {
		return maxLimit, nil
	}
	return parsed, nil
}

func parseOffsetQuery(c *fiber.Ctx) (int, error) {
	val := strings.TrimSpace(c.Query("offset"))
	if val == "" {
		return 0, nil
	}
	parsed, err := strconv.Atoi(val)
	if err != nil || parsed < 0 {
		return 0, fiber.NewError(fiber.StatusBadRequest, "offset invalid")
	}
	return parsed, nil
}

func parseInt64Param(c *fiber.Ctx, name string) (int64, error) {
	val := strings.TrimSpace(c.Params(name))
	if val == "" {
		return 0, fiber.NewError(fiber.StatusBadRequest, name+" required")
	}
	parsed, err := strconv.ParseInt(val, 10, 64)
	if err != nil || parsed <= 0 {
		return 0, fiber.NewError(fiber.StatusBadRequest, name+" invalid")
	}
	return parsed, nil
}

