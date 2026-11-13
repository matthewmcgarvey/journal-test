package api

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"accounting-service/internal/domain"
	"accounting-service/internal/service"
)

type repositoryStub struct {
	createAccountErr  error
	createTransferErr error
}

func (r *repositoryStub) ListAccounts(context.Context) ([]domain.Account, error) {
	return []domain.Account{}, nil
}

func (r *repositoryStub) GetAccount(context.Context, int64) (domain.Account, error) {
	return domain.Account{}, domain.ErrNotFound
}

func (r *repositoryStub) CreateAccount(_ context.Context, externalID string, trackBalance bool) (domain.Account, error) {
	if r.createAccountErr != nil {
		return domain.Account{}, r.createAccountErr
	}
	return domain.Account{ExternalID: externalID, TrackBalance: trackBalance}, nil
}

func (r *repositoryStub) ListTransfers(context.Context) ([]domain.Transfer, error) {
	return []domain.Transfer{}, nil
}

func (r *repositoryStub) GetTransfer(context.Context, int64) (domain.Transfer, error) {
	return domain.Transfer{}, domain.ErrNotFound
}

func (r *repositoryStub) CreateTransfer(_ context.Context, transfer domain.Transfer) (domain.Transfer, error) {
	if r.createTransferErr != nil {
		return domain.Transfer{}, r.createTransferErr
	}
	return transfer, nil
}

func (r *repositoryStub) ListAccountBalances(context.Context) ([]domain.AccountBalance, error) {
	return []domain.AccountBalance{}, nil
}

func TestCreateEndpointsValidateWrapperAndMapErrors(t *testing.T) {
	tests := []struct {
		name       string
		method     string
		path       string
		body       string
		repo       *repositoryStub
		wantStatus int
		wantBody   string
	}{
		{
			name:       "missing account wrapper",
			method:     http.MethodPost,
			path:       "/api/v1/accounts",
			body:       `{}`,
			wantStatus: http.StatusBadRequest,
			wantBody:   `"error":"account object is required"`,
		},
		{
			name:       "account unique conflict",
			method:     http.MethodPost,
			path:       "/api/v1/accounts",
			body:       `{"account":{"external_id":"duplicate"}}`,
			repo:       &repositoryStub{createAccountErr: domain.ErrConflict},
			wantStatus: http.StatusConflict,
			wantBody:   `"error":"external_id already exists"`,
		},
		{
			name:       "missing transfer wrapper",
			method:     http.MethodPost,
			path:       "/api/v1/transfers",
			body:       `{}`,
			wantStatus: http.StatusBadRequest,
			wantBody:   `"error":"transfer object is required"`,
		},
		{
			name:       "insufficient balance",
			method:     http.MethodPost,
			path:       "/api/v1/transfers",
			body:       `{"transfer":{"external_id":"t1","debit_account_id":1,"credit_account_id":2,"amount":10}}`,
			repo:       &repositoryStub{createTransferErr: domain.ErrInsufficientFunds},
			wantStatus: http.StatusUnprocessableEntity,
			wantBody:   `"error":"insufficient funds for debit account"`,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			repository := test.repo
			if repository == nil {
				repository = &repositoryStub{}
			}
			router := NewRouter(service.New(repository))
			request := httptest.NewRequest(test.method, test.path, strings.NewReader(test.body))
			request.Header.Set("Content-Type", "application/json")
			response := httptest.NewRecorder()

			router.ServeHTTP(response, request)

			if response.Code != test.wantStatus {
				t.Fatalf("status = %d, want %d; body: %s", response.Code, test.wantStatus, response.Body.String())
			}
			if !strings.Contains(response.Body.String(), test.wantBody) {
				t.Fatalf("body = %s, want it to contain %s", response.Body.String(), test.wantBody)
			}
		})
	}
}

func TestShowMissingAccountReturnsNotFound(t *testing.T) {
	router := NewRouter(service.New(&repositoryStub{}))
	response := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, "/api/v1/accounts/123", nil)

	router.ServeHTTP(response, request)

	if response.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusNotFound)
	}
	if !strings.Contains(response.Body.String(), `"error":"record not found"`) {
		t.Fatalf("body = %s, want a not-found error", response.Body.String())
	}
}
