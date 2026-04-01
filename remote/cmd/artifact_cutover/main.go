package main

import (
	"flag"
	"fmt"
	"log"
	"strings"

	"family_teacher_remote/internal/artifactsync"
	"family_teacher_remote/internal/config"
	"family_teacher_remote/internal/db"
	"family_teacher_remote/internal/storage"
)

type repeatedCredentialFlag []string

func (r *repeatedCredentialFlag) String() string {
	return strings.Join(*r, ",")
}

func (r *repeatedCredentialFlag) Set(value string) error {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return fmt.Errorf("student credential must not be empty")
	}
	*r = append(*r, trimmed)
	return nil
}

func main() {
	var studentFlags repeatedCredentialFlag
	dropLegacy := flag.Bool("drop-legacy", false, "drop legacy row-level sync tables after successful artifact conversion")
	confirmHardCutover := flag.Bool("confirm-hard-cutover", false, "required together with -drop-legacy")
	flag.Var(&studentFlags, "student", "student credential in username=password form; repeat for each student")
	flag.Parse()

	if *dropLegacy && !*confirmHardCutover {
		log.Fatal("drop-legacy requires -confirm-hard-cutover")
	}
	if len(studentFlags) == 0 {
		log.Fatal("at least one -student username=password is required")
	}

	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config load failed: %v", err)
	}
	store, err := db.NewStore(cfg.DatabaseDSN)
	if err != nil {
		log.Fatalf("db init failed: %v", err)
	}
	storageSvc, err := storage.New(storage.Config{
		Root:           cfg.StorageRoot,
		BundleMaxBytes: cfg.BundleMaxBytes,
	})
	if err != nil {
		log.Fatalf("storage init failed: %v", err)
	}

	credentials := make([]artifactsync.LegacyStudentCredential, 0, len(studentFlags))
	for _, raw := range studentFlags {
		parts := strings.SplitN(raw, "=", 2)
		if len(parts) != 2 {
			log.Fatalf("student credential must use username=password: %s", raw)
		}
		username := strings.TrimSpace(parts[0])
		password := parts[1]
		if username == "" || password == "" {
			log.Fatalf("student credential must use username=password: %s", raw)
		}
		credentials = append(credentials, artifactsync.LegacyStudentCredential{
			Username: username,
			Password: password,
		})
	}

	summary, err := artifactsync.RunLegacyStudentCutover(
		store.DB,
		storageSvc,
		credentials,
		*dropLegacy,
	)
	if err != nil {
		log.Fatalf("artifact cutover failed: %v", err)
	}
	log.Printf(
		"artifact cutover complete: students=%d sessions=%d progress=%d artifacts=%d users=%d dropped_legacy=%t",
		summary.StudentsResolved,
		summary.LegacySessions,
		summary.LegacyProgress,
		summary.ArtifactsBuilt,
		summary.UsersRefreshed,
		summary.DroppedLegacy,
	)
}
