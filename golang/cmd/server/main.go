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

	dbConn, err := db.Connect(cfg)
	if err != nil {
		log.Fatalf("database connection failed: %v", err)
	}
	defer dbConn.Close()

	r := api.NewRouter(dbConn)
	addr := ":" + strconv.Itoa(cfg.Port)
	log.Printf("starting accounting API on %s", addr)
	if err := r.Run(addr); err != nil {
		log.Fatalf("http server failed: %v", err)
	}
}
