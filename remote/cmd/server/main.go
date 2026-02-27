package main

import (
	"log"

	"family_teacher_remote/internal/config"
	"family_teacher_remote/internal/db"
	"family_teacher_remote/internal/httpserver"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config load failed: %v", err)
	}

	store, err := db.NewStore(cfg.DatabaseDSN)
	if err != nil {
		log.Fatalf("db init failed: %v", err)
	}

	server, err := httpserver.New(cfg, store)
	if err != nil {
		log.Fatalf("server init failed: %v", err)
	}
	if err := server.Listen(cfg.HTTPAddr); err != nil {
		log.Fatalf("server failed: %v", err)
	}
}
