package httpserver

import (
	"family_teacher_remote/internal/config"
	"family_teacher_remote/internal/db"
	"family_teacher_remote/internal/httpserver/handlers"

	"github.com/gofiber/fiber/v2"
)

type Server struct {
	app *fiber.App
}

func New(cfg config.Config, store *db.Store) *Server {
	app := fiber.New()

	handlerDeps := handlers.Dependencies{
		Config: cfg,
		Store:  store,
	}
	registerRoutes(app, handlerDeps)

	return &Server{app: app}
}

func (s *Server) Listen(addr string) error {
	return s.app.Listen(addr)
}
