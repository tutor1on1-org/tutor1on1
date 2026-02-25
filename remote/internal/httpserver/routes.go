package httpserver

import (
	"family_teacher_remote/internal/httpserver/handlers"

	"github.com/gofiber/fiber/v2"
)

func registerRoutes(app *fiber.App, deps handlers.Dependencies) {
	health := handlers.NewHealthHandler()
	auth := handlers.NewAuthHandler(deps)

	app.Get("/health", health.Check)

	api := app.Group("/api")
	api.Post("/auth/register", auth.Register)
	api.Post("/auth/login", auth.Login)
	api.Post("/auth/refresh", auth.Refresh)
	api.Post("/auth/revoke", auth.Revoke)
}
