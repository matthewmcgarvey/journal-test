package main

import (
	"log"

	"accounting-service/internal/config"
	"accounting-service/internal/db"
)

func main() {
	cfg := config.Load()
	if err := db.RunMigrations(cfg); err != nil {
		log.Fatalf("migration failed: %v", err)
	}
	log.Println("database migrations complete")
}
