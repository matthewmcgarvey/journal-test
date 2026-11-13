package main

import (
	"log"
	"strconv"

	"accounting-service/internal/api"
	"accounting-service/internal/config"
	"accounting-service/internal/db"
	"accounting-service/internal/repository"
	"accounting-service/internal/service"
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

	accountingService := service.New(repository.NewPostgres(dbConn))
	r := api.NewRouter(accountingService)
	addr := ":" + strconv.Itoa(cfg.Port)
	log.Printf("starting accounting API on %s", addr)
	if err := r.Run(addr); err != nil {
		log.Fatalf("http server failed: %v", err)
	}
}
