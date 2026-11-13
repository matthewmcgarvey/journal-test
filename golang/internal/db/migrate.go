package db

import (
	"errors"
	"fmt"
	"path/filepath"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/postgres"
	_ "github.com/golang-migrate/migrate/v4/source/file"

	"accounting-service/internal/config"
)

func RunMigrations(cfg config.Config) error {
	absPath, err := filepath.Abs("./migrations")
	if err != nil {
		return fmt.Errorf("resolve migrations path: %w", err)
	}

	sourceURL := "file://" + filepath.ToSlash(absPath)
	instance, err := migrate.New(sourceURL, cfg.DSN())
	if err != nil {
		return fmt.Errorf("create migration runner: %w", err)
	}
	defer instance.Close()

	if err := instance.Up(); err != nil && !errors.Is(err, migrate.ErrNoChange) {
		return fmt.Errorf("apply migrations: %w", err)
	}

	return nil
}
