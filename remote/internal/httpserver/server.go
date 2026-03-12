package httpserver

import (
	"family_teacher_remote/internal/config"
	"family_teacher_remote/internal/db"
	"family_teacher_remote/internal/httpserver/handlers"
	"family_teacher_remote/internal/mailer"
	"family_teacher_remote/internal/storage"

	"github.com/gofiber/fiber/v2"
)

type Server struct {
	app *fiber.App
}

func New(cfg config.Config, store *db.Store) (*Server, error) {
	app := fiber.New(fiber.Config{
		BodyLimit: int(cfg.BundleMaxBytes) + (1 << 20),
	})

	storageSvc, err := storage.New(storage.Config{
		Root:           cfg.StorageRoot,
		BundleMaxBytes: cfg.BundleMaxBytes,
	})
	if err != nil {
		return nil, err
	}

	handlerDeps := handlers.Dependencies{
		Config:  cfg,
		Store:   store,
		Storage: storageSvc,
		Mailer:  mailer.New(cfg),
	}
	if err := handlers.EnsureDefaultAdmin(store.DB); err != nil {
		return nil, err
	}
	registerRoutes(app, handlerDeps)

	return &Server{app: app}, nil
}

func (s *Server) Listen(addr string) error {
	return s.app.Listen(addr)
}
