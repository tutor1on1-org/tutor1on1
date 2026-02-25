package middleware

import (
	"strings"
	"sync"
	"time"

	"github.com/gofiber/fiber/v2"
)

type RateLimiter struct {
	max    int
	window time.Duration
	mu     sync.Mutex
	state  map[string]*rateEntry
}

type rateEntry struct {
	count   int
	resetAt time.Time
}

func NewRateLimiter(max int, window time.Duration) *RateLimiter {
	if max <= 0 {
		max = 1
	}
	if window <= 0 {
		window = time.Minute
	}
	return &RateLimiter{
		max:    max,
		window: window,
		state:  make(map[string]*rateEntry),
	}
}

func (l *RateLimiter) Allow(key string) bool {
	now := time.Now()
	l.mu.Lock()
	defer l.mu.Unlock()
	entry, ok := l.state[key]
	if !ok || now.After(entry.resetAt) {
		l.state[key] = &rateEntry{
			count:   1,
			resetAt: now.Add(l.window),
		}
		return true
	}
	if entry.count >= l.max {
		return false
	}
	entry.count++
	return true
}

func (l *RateLimiter) Handler(keyFn func(*fiber.Ctx) string) fiber.Handler {
	if keyFn == nil {
		keyFn = KeyByIP
	}
	return func(c *fiber.Ctx) error {
		key := keyFn(c)
		if key == "" {
			return fiber.NewError(fiber.StatusTooManyRequests, "rate limit exceeded")
		}
		if !l.Allow(key) {
			return fiber.NewError(fiber.StatusTooManyRequests, "rate limit exceeded")
		}
		return c.Next()
	}
}

func KeyByIP(c *fiber.Ctx) string {
	ip := strings.TrimSpace(c.Get("X-Forwarded-For"))
	if ip != "" {
		parts := strings.Split(ip, ",")
		if len(parts) > 0 {
			candidate := strings.TrimSpace(parts[0])
			if candidate != "" {
				return candidate
			}
		}
	}
	ip = strings.TrimSpace(c.Get("X-Real-IP"))
	if ip != "" {
		return ip
	}
	return strings.TrimSpace(c.IP())
}

