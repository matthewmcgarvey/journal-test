package domain

import "errors"

var (
	ErrConflict          = errors.New("record already exists")
	ErrInsufficientFunds = errors.New("insufficient funds")
	ErrNotFound          = errors.New("record not found")
	ErrValidation        = errors.New("invalid input")
)
