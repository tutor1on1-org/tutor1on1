package httpserver

import (
	"time"

	"family_teacher_remote/internal/httpserver/handlers"
	"family_teacher_remote/internal/httpserver/middleware"

	"github.com/gofiber/fiber/v2"
)

func registerRoutes(app *fiber.App, deps handlers.Dependencies) {
	health := handlers.NewHealthHandler()
	auth := handlers.NewAuthHandler(deps)
	bundles := handlers.NewBundlesHandler(deps)

	app.Get("/health", health.Check)

	api := app.Group("/api")
	authLimiterRegister := middleware.NewRateLimiter(5, time.Minute)
	authLimiterLogin := middleware.NewRateLimiter(10, time.Minute)
	authLimiterRecovery := middleware.NewRateLimiter(3, time.Minute)
	authLimiterChange := middleware.NewRateLimiter(5, time.Minute)
	authLimiterRefresh := middleware.NewRateLimiter(20, time.Minute)

	api.Post("/auth/register", authLimiterRegister.Handler(middleware.KeyByIP), auth.Register)
	api.Post("/auth/register-student", authLimiterRegister.Handler(middleware.KeyByIP), auth.RegisterStudent)
	api.Post("/auth/register-teacher", authLimiterRegister.Handler(middleware.KeyByIP), auth.RegisterTeacher)
	api.Post("/auth/login", authLimiterLogin.Handler(middleware.KeyByIP), auth.Login)
	api.Post("/auth/change-password", authLimiterChange.Handler(middleware.KeyByIP), auth.ChangePassword)
	api.Post("/auth/request-recovery", authLimiterRecovery.Handler(middleware.KeyByIP), auth.RequestRecovery)
	api.Post("/auth/reset-password", authLimiterRecovery.Handler(middleware.KeyByIP), auth.ResetPassword)
	api.Post("/auth/refresh", authLimiterRefresh.Handler(middleware.KeyByIP), auth.Refresh)
	api.Post("/auth/revoke", authLimiterRefresh.Handler(middleware.KeyByIP), auth.Revoke)
	api.Post("/bundles/upload", bundles.Upload)
	api.Get("/bundles/download", bundles.Download)
}
