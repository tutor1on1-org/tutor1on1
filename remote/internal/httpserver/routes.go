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
	catalog := handlers.NewCatalogHandler(deps)
	enrollments := handlers.NewEnrollmentHandler(deps)
	teacherCourses := handlers.NewTeacherCoursesHandler(deps)
	userKeys := handlers.NewUserKeysHandler(deps)
	sessionSync := handlers.NewSessionSyncHandler(deps)
	progressSync := handlers.NewProgressSyncHandler(deps)

	app.Get("/health", health.Check)

	api := app.Group("/api")
	authLimiterRegister := middleware.NewRateLimiter(5, time.Minute)
	authLimiterLogin := middleware.NewRateLimiter(10, time.Minute)
	authLimiterRecovery := middleware.NewRateLimiter(3, time.Minute)
	authLimiterChange := middleware.NewRateLimiter(5, time.Minute)
	authLimiterRefresh := middleware.NewRateLimiter(20, time.Minute)
	catalogLimiter := middleware.NewRateLimiter(60, time.Minute)
	enrollmentLimiter := middleware.NewRateLimiter(20, time.Minute)
	syncLimiter := middleware.NewRateLimiter(30, time.Minute)

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

	api.Get("/catalog/teachers", catalogLimiter.Handler(middleware.KeyByIP), catalog.ListTeachers)
	api.Get("/catalog/courses", catalogLimiter.Handler(middleware.KeyByIP), catalog.ListCourses)

	api.Get("/teacher/courses", teacherCourses.ListCourses)
	api.Post("/teacher/courses", teacherCourses.CreateCourse)
	api.Post("/teacher/courses/:id/publish", teacherCourses.PublishCourse)
	api.Post("/teacher/courses/:id/delete", teacherCourses.DeleteCourse)
	api.Post("/teacher/courses/:id/bundles", teacherCourses.EnsureBundle)
	api.Get("/teacher/courses/:id/bundle-versions", bundles.ListTeacherCourseBundleVersions)
	api.Post("/teacher/courses/:id/bundle-versions/:versionId/delete", bundles.DeleteTeacherCourseBundleVersion)

	api.Post("/enrollment-requests", enrollmentLimiter.Handler(middleware.KeyByIP), enrollments.CreateRequest)
	api.Get("/enrollment-requests", enrollments.ListStudentRequests)
	api.Get("/enrollments", enrollments.ListEnrollments)
	api.Post("/enrollments/:id/quit-request", enrollmentLimiter.Handler(middleware.KeyByIP), enrollments.CreateQuitRequest)
	api.Get("/enrollments/quit-requests", enrollments.ListStudentQuitRequests)
	api.Get("/enrollments/deletion-events", syncLimiter.Handler(middleware.KeyByIP), enrollments.ListDeletionEvents)
	api.Get("/teacher/enrollment-requests", enrollments.ListTeacherRequests)
	api.Post("/teacher/enrollment-requests/:id/approve", enrollments.ApproveRequest)
	api.Post("/teacher/enrollment-requests/:id/reject", enrollments.RejectRequest)
	api.Get("/teacher/quit-requests", enrollments.ListTeacherQuitRequests)
	api.Post("/teacher/quit-requests/:id/approve", enrollments.ApproveQuitRequest)
	api.Post("/teacher/quit-requests/:id/reject", enrollments.RejectQuitRequest)

	api.Get("/keys/self", userKeys.GetSelf)
	api.Post("/keys/self", userKeys.UpsertSelf)
	api.Get("/keys/course", userKeys.GetCourseKeys)

	api.Post("/sessions/sync/upload", syncLimiter.Handler(middleware.KeyByIP), sessionSync.Upload)
	api.Get("/sessions/sync/list", syncLimiter.Handler(middleware.KeyByIP), sessionSync.List)
	api.Post("/progress/sync/upload", syncLimiter.Handler(middleware.KeyByIP), progressSync.Upload)
	api.Post("/progress/sync/upload-batch", syncLimiter.Handler(middleware.KeyByIP), progressSync.UploadBatch)
	api.Get("/progress/sync/list", syncLimiter.Handler(middleware.KeyByIP), progressSync.List)
}
