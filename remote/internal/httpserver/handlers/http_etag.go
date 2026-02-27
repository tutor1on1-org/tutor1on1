package handlers

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"strings"

	"github.com/gofiber/fiber/v2"
)

func respondJSONWithETag(c *fiber.Ctx, payload interface{}) error {
	body, err := json.Marshal(payload)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "response encode failed")
	}
	etag := buildWeakETag(body)
	c.Set(fiber.HeaderETag, etag)
	if matchesIfNoneMatch(c.Get(fiber.HeaderIfNoneMatch), etag) {
		return c.SendStatus(fiber.StatusNotModified)
	}
	c.Set(fiber.HeaderContentType, fiber.MIMEApplicationJSON)
	return c.Send(body)
}

func buildWeakETag(body []byte) string {
	sum := sha256.Sum256(body)
	shortHash := hex.EncodeToString(sum[:16])
	return `W/"` + shortHash + `"`
}

func matchesIfNoneMatch(ifNoneMatch string, etag string) bool {
	normalizedTarget := normalizeETagToken(etag)
	if normalizedTarget == "" {
		return false
	}
	for _, token := range strings.Split(ifNoneMatch, ",") {
		trimmed := strings.TrimSpace(token)
		if trimmed == "*" {
			return true
		}
		if normalizeETagToken(trimmed) == normalizedTarget {
			return true
		}
	}
	return false
}

func normalizeETagToken(value string) string {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return ""
	}
	weakTrimmed := strings.TrimPrefix(trimmed, "W/")
	weakTrimmed = strings.TrimPrefix(weakTrimmed, "w/")
	return strings.Trim(weakTrimmed, `"`)
}
