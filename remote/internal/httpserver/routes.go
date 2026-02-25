package httpserver

import (
	"family_teacher_remote/internal/httpserver/handlers"

	"github.com/gofiber/fiber/v2"
)

func registerRoutes(app *fiber.App, deps handlers.Dependencies) {
	health := handlers.NewHealthHandler()
	auth := handlers.NewAuthHandler(deps)
	bundles := handlers.NewBundlesHandler(deps)

	app.Get("/health", health.Check)

	api := app.Group("/api")
	api.Post("/auth/register", auth.Register)
	api.Post("/auth/register-student", auth.RegisterStudent)
	api.Post("/auth/register-teacher", auth.RegisterTeacher)
	api.Post("/auth/login", auth.Login)
	api.Post("/auth/change-password", auth.ChangePassword)
	api.Post("/auth/request-recovery", auth.RequestRecovery)
	api.Post("/auth/reset-password", auth.ResetPassword)
	api.Post("/auth/refresh", auth.Refresh)
	api.Post("/auth/revoke", auth.Revoke)
	api.Post("/bundles/upload", bundles.Upload)
	api.Get("/bundles/download", bundles.Download)
}
