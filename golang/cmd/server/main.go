package main

import (
	"log"
	"strconv"

	"accounting-service/internal/api"
	"accounting-service/internal/config"
	"accounting-service/internal/db"
)

func main() {
	cfg := config.Load()

	if err := db.RunMigrations(cfg); err != nil {
		log.Fatalf("database migrations failed: %v", err)
	}

	r := api.NewRouter()
	addr := ":" + strconv.Itoa(cfg.Port)
	log.Printf("starting accounting API on %s", addr)
	if err := r.Run(addr); err != nil {
		log.Fatalf("http server failed: %v", err)
	}
}
