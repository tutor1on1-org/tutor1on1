package httpserver

import (
	"database/sql"
	"log"
	"strings"
	"time"

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

const (
	studentKpArtifactGCGracePeriod = time.Hour
	studentKpArtifactGCInterval    = 15 * time.Minute
)

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
	if removed, err := sweepStudentKpArtifacts(store.DB, storageSvc); err != nil {
		log.Printf("student artifact cleanup failed: %v", err)
	} else if removed > 0 {
		log.Printf("student artifact cleanup removed %d unreferenced files", removed)
	}
	registerRoutes(app, handlerDeps)
	go runStudentKpArtifactGC(store.DB, storageSvc)

	return &Server{app: app}, nil
}

func (s *Server) Listen(addr string) error {
	return s.app.Listen(addr)
}

func runStudentKpArtifactGC(database *sql.DB, storageSvc *storage.Service) {
	ticker := time.NewTicker(studentKpArtifactGCInterval)
	defer ticker.Stop()
	for range ticker.C {
		removed, err := sweepStudentKpArtifacts(database, storageSvc)
		if err != nil {
			log.Printf("student artifact cleanup failed: %v", err)
			continue
		}
		if removed > 0 {
			log.Printf("student artifact cleanup removed %d unreferenced files", removed)
		}
	}
}

func sweepStudentKpArtifacts(
	database *sql.DB,
	storageSvc *storage.Service,
) (int, error) {
	referencedRelPaths, err := readReferencedStudentKpArtifactPaths(database)
	if err != nil {
		return 0, err
	}
	return storageSvc.RemoveUnreferencedStudentKpArtifacts(
		referencedRelPaths,
		time.Now().UTC().Add(-studentKpArtifactGCGracePeriod),
	)
}

func readReferencedStudentKpArtifactPaths(database *sql.DB) (map[string]struct{}, error) {
	rows, err := database.Query(
		`SELECT storage_rel_path
		 FROM student_kp_artifacts
		 UNION
		 SELECT storage_rel_path
		 FROM artifact_state1_items
		 WHERE artifact_class = 'student_kp'`,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	referencedRelPaths := map[string]struct{}{}
	for rows.Next() {
		var relPath string
		if err := rows.Scan(&relPath); err != nil {
			return nil, err
		}
		if trimmed := strings.TrimSpace(relPath); trimmed != "" {
			referencedRelPaths[trimmed] = struct{}{}
		}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return referencedRelPaths, nil
}
