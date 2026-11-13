package service

import (
	"context"
	"errors"
	"testing"

	"accounting-service/internal/domain"
)

type repositoryStub struct {
	createdExternalID   string
	createdTracked      bool
	createAccountCalls  int
	createTransferCalls int
}

func (r *repositoryStub) ListAccounts(context.Context) ([]domain.Account, error) {
	return nil, nil
}

func (r *repositoryStub) GetAccount(context.Context, int64) (domain.Account, error) {
	return domain.Account{}, nil
}

func (r *repositoryStub) CreateAccount(_ context.Context, externalID string, trackBalance bool) (domain.Account, error) {
	r.createdExternalID = externalID
	r.createdTracked = trackBalance
	r.createAccountCalls++
	return domain.Account{ExternalID: externalID, TrackBalance: trackBalance}, nil
}

func (r *repositoryStub) ListTransfers(context.Context) ([]domain.Transfer, error) {
	return nil, nil
}

func (r *repositoryStub) GetTransfer(context.Context, int64) (domain.Transfer, error) {
	return domain.Transfer{}, nil
}

func (r *repositoryStub) CreateTransfer(_ context.Context, transfer domain.Transfer) (domain.Transfer, error) {
	r.createTransferCalls++
	return transfer, nil
}

func (r *repositoryStub) ListAccountBalances(context.Context) ([]domain.AccountBalance, error) {
	return nil, nil
}

func TestCreateAccountDefaultsTrackingAndValidatesExternalID(t *testing.T) {
	repository := &repositoryStub{}
	svc := New(repository)

	account, err := svc.CreateAccount(context.Background(), CreateAccountInput{ExternalID: "acct-default"})
	if err != nil {
		t.Fatalf("CreateAccount() error = %v", err)
	}
	if !account.TrackBalance || !repository.createdTracked {
		t.Fatal("expected track_balance to default to true")
	}

	untracked := false
	_, err = svc.CreateAccount(context.Background(), CreateAccountInput{
		ExternalID:   "acct-untracked",
		TrackBalance: &untracked,
	})
	if err != nil {
		t.Fatalf("CreateAccount(untracked) error = %v", err)
	}
	if repository.createdTracked {
		t.Fatal("expected explicit false track_balance to be preserved")
	}

	_, err = svc.CreateAccount(context.Background(), CreateAccountInput{ExternalID: " \t "})
	if !errors.Is(err, domain.ErrValidation) {
		t.Fatalf("CreateAccount(blank) error = %v, want ErrValidation", err)
	}
	if repository.createAccountCalls != 2 {
		t.Fatalf("CreateAccount called repository %d times, want 2", repository.createAccountCalls)
	}
}

func TestCreateTransferValidatesBeforeCallingRepository(t *testing.T) {
	repository := &repositoryStub{}
	svc := New(repository)

	valid := domain.Transfer{
		ExternalID:      "transfer-valid",
		DebitAccountID:  1,
		CreditAccountID: 2,
		Amount:          1,
	}
	if _, err := svc.CreateTransfer(context.Background(), valid); err != nil {
		t.Fatalf("CreateTransfer(valid) error = %v", err)
	}

	tests := []struct {
		name     string
		transfer domain.Transfer
	}{
		{name: "blank external id", transfer: domain.Transfer{DebitAccountID: 1, CreditAccountID: 2, Amount: 1}},
		{name: "missing debit account", transfer: domain.Transfer{ExternalID: "bad", CreditAccountID: 2, Amount: 1}},
		{name: "missing credit account", transfer: domain.Transfer{ExternalID: "bad", DebitAccountID: 1, Amount: 1}},
		{name: "same accounts", transfer: domain.Transfer{ExternalID: "bad", DebitAccountID: 1, CreditAccountID: 1, Amount: 1}},
		{name: "non-positive amount", transfer: domain.Transfer{ExternalID: "bad", DebitAccountID: 1, CreditAccountID: 2, Amount: 0}},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			_, err := svc.CreateTransfer(context.Background(), test.transfer)
			if !errors.Is(err, domain.ErrValidation) {
				t.Fatalf("CreateTransfer() error = %v, want ErrValidation", err)
			}
		})
	}

	if repository.createTransferCalls != 1 {
		t.Fatalf("CreateTransfer called repository %d times, want 1", repository.createTransferCalls)
	}
}
