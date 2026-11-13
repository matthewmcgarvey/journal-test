package config

import (
	"fmt"
	"os"
	"strconv"
)

type Config struct {
	Env         string
	Port        int
	DatabaseURL string
}

func Load() Config {
	cfg := Config{
		Env:         getEnv("APP_ENV", "development"),
		Port:        getEnvInt("APP_PORT", 8080),
		DatabaseURL: getEnv("DATABASE_URL", "postgres://app:app@localhost:5432/accounting?sslmode=disable"),
	}

	if cfg.Env == "production" {
		cfg.DatabaseURL = getEnv("DATABASE_URL", cfg.DatabaseURL)
	}

	return cfg
}

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok && value != "" {
		return value
	}
	return fallback
}

func getEnvInt(key string, fallback int) int {
	if value, ok := os.LookupEnv(key); ok && value != "" {
		parsed, err := strconv.Atoi(value)
		if err == nil {
			return parsed
		}
	}
	return fallback
}

func (c Config) DSN() string {
	return c.DatabaseURL
}

func (c Config) PostgresURL() string {
	return c.DatabaseURL
}

func Example() string {
	return fmt.Sprintf("database=%s port=%d", "accounting", 5432)
}
