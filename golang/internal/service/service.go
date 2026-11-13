package service

import (
	"context"
	"strings"

	"accounting-service/internal/domain"
)

type Repository interface {
	ListAccounts(context.Context) ([]domain.Account, error)
	GetAccount(context.Context, int64) (domain.Account, error)
	CreateAccount(context.Context, string, bool) (domain.Account, error)
	ListTransfers(context.Context) ([]domain.Transfer, error)
	GetTransfer(context.Context, int64) (domain.Transfer, error)
	CreateTransfer(context.Context, domain.Transfer) (domain.Transfer, error)
	ListAccountBalances(context.Context) ([]domain.AccountBalance, error)
}

type Service struct {
	repository Repository
}

type CreateAccountInput struct {
	ExternalID   string
	TrackBalance *bool
}

func New(repository Repository) *Service {
	return &Service{repository: repository}
}

func (s *Service) ListAccounts(ctx context.Context) ([]domain.Account, error) {
	return s.repository.ListAccounts(ctx)
}

func (s *Service) GetAccount(ctx context.Context, id int64) (domain.Account, error) {
	if id < 1 {
		return domain.Account{}, domain.ErrValidation
	}
	return s.repository.GetAccount(ctx, id)
}

func (s *Service) CreateAccount(ctx context.Context, input CreateAccountInput) (domain.Account, error) {
	if strings.TrimSpace(input.ExternalID) == "" {
		return domain.Account{}, domain.ErrValidation
	}
	trackBalance := true
	if input.TrackBalance != nil {
		trackBalance = *input.TrackBalance
	}
	return s.repository.CreateAccount(ctx, input.ExternalID, trackBalance)
}

func (s *Service) ListTransfers(ctx context.Context) ([]domain.Transfer, error) {
	return s.repository.ListTransfers(ctx)
}

func (s *Service) GetTransfer(ctx context.Context, id int64) (domain.Transfer, error) {
	if id < 1 {
		return domain.Transfer{}, domain.ErrValidation
	}
	return s.repository.GetTransfer(ctx, id)
}

func (s *Service) CreateTransfer(ctx context.Context, transfer domain.Transfer) (domain.Transfer, error) {
	if strings.TrimSpace(transfer.ExternalID) == "" ||
		transfer.DebitAccountID < 1 ||
		transfer.CreditAccountID < 1 ||
		transfer.DebitAccountID == transfer.CreditAccountID ||
		transfer.Amount <= 0 {
		return domain.Transfer{}, domain.ErrValidation
	}
	return s.repository.CreateTransfer(ctx, transfer)
}

func (s *Service) ListAccountBalances(ctx context.Context) ([]domain.AccountBalance, error) {
	return s.repository.ListAccountBalances(ctx)
}
