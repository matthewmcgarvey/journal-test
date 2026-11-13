package repository

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"accounting-service/internal/domain"
	sqlcdb "accounting-service/internal/repository/db"

	"github.com/jackc/pgx/v5/pgconn"
)

type Postgres struct {
	db      *sql.DB
	queries *sqlcdb.Queries
}

func NewPostgres(db *sql.DB) *Postgres {
	return &Postgres{
		db:      db,
		queries: sqlcdb.New(db),
	}
}

func (p *Postgres) ListAccounts(ctx context.Context) ([]domain.Account, error) {
	rows, err := p.queries.ListAccounts(ctx)
	if err != nil {
		return nil, fmt.Errorf("list accounts: %w", err)
	}
	accounts := make([]domain.Account, 0, len(rows))
	for _, row := range rows {
		account, err := accountFromRow(row.ID, row.ExternalID, row.TrackBalance, row.CreatedAt, row.CurrentBalance, row.HasBalanceSnapshot)
		if err != nil {
			return nil, err
		}
		accounts = append(accounts, account)
	}
	return accounts, nil
}

func (p *Postgres) GetAccount(ctx context.Context, id int64) (domain.Account, error) {
	row, err := p.queries.GetAccount(ctx, id)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.Account{}, domain.ErrNotFound
	}
	if err != nil {
		return domain.Account{}, fmt.Errorf("get account: %w", err)
	}
	account, err := accountFromRow(row.ID, row.ExternalID, row.TrackBalance, row.CreatedAt, row.CurrentBalance, row.HasBalanceSnapshot)
	if err != nil {
		return domain.Account{}, err
	}
	return account, nil
}

func (p *Postgres) CreateAccount(ctx context.Context, externalID string, trackBalance bool) (domain.Account, error) {
	tx, err := p.db.BeginTx(ctx, nil)
	if err != nil {
		return domain.Account{}, fmt.Errorf("begin account creation: %w", err)
	}
	defer tx.Rollback()

	queries := sqlcdb.New(tx)
	row, err := queries.InsertAccount(ctx, sqlcdb.InsertAccountParams{
		ExternalID:   externalID,
		TrackBalance: trackBalance,
	})
	if err != nil {
		if isUniqueViolation(err) {
			return domain.Account{}, domain.ErrConflict
		}
		return domain.Account{}, fmt.Errorf("insert account: %w", err)
	}

	account := domain.Account{
		ID:           int64(row.ID),
		ExternalID:   row.ExternalID,
		TrackBalance: row.TrackBalance,
		CreatedAt:    row.CreatedAt,
	}
	if trackBalance {
		if err := queries.InsertInitialBalance(ctx, row.ID); err != nil {
			return domain.Account{}, fmt.Errorf("insert initial balance: %w", err)
		}
		zero := int64(0)
		account.CurrentBalance = &zero
	}

	if err := tx.Commit(); err != nil {
		return domain.Account{}, fmt.Errorf("commit account creation: %w", err)
	}
	return account, nil
}

func (p *Postgres) ListTransfers(ctx context.Context) ([]domain.Transfer, error) {
	rows, err := p.queries.ListTransfers(ctx)
	if err != nil {
		return nil, fmt.Errorf("list transfers: %w", err)
	}
	transfers := make([]domain.Transfer, 0, len(rows))
	for _, row := range rows {
		transfers = append(transfers, transferFromRow(row))
	}
	return transfers, nil
}

func (p *Postgres) GetTransfer(ctx context.Context, id int64) (domain.Transfer, error) {
	row, err := p.queries.GetTransfer(ctx, id)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.Transfer{}, domain.ErrNotFound
	}
	if err != nil {
		return domain.Transfer{}, fmt.Errorf("get transfer: %w", err)
	}
	return transferFromRow(row), nil
}

func (p *Postgres) CreateTransfer(ctx context.Context, transfer domain.Transfer) (domain.Transfer, error) {
	tx, err := p.db.BeginTx(ctx, nil)
	if err != nil {
		return domain.Transfer{}, fmt.Errorf("begin transfer: %w", err)
	}
	defer tx.Rollback()

	queries := sqlcdb.New(tx)
	accounts, err := queries.LockTransferAccounts(ctx, sqlcdb.LockTransferAccountsParams{
		DebitAccountID:  transfer.DebitAccountID,
		CreditAccountID: transfer.CreditAccountID,
	})
	if err != nil {
		return domain.Transfer{}, fmt.Errorf("lock transfer accounts: %w", err)
	}
	tracked := make(map[int64]bool, len(accounts))
	for _, account := range accounts {
		tracked[int64(account.ID)] = account.TrackBalance
	}
	if len(tracked) != 2 {
		return domain.Transfer{}, domain.ErrNotFound
	}

	balances := make(map[int64]int64, 2)
	for _, accountID := range []int64{transfer.DebitAccountID, transfer.CreditAccountID} {
		if !tracked[accountID] {
			continue
		}
		balance, err := queries.LatestAccountBalance(ctx, accountID)
		if errors.Is(err, sql.ErrNoRows) {
			return domain.Transfer{}, fmt.Errorf("tracked account %d has no balance snapshot", accountID)
		}
		if err != nil {
			return domain.Transfer{}, fmt.Errorf("load latest balance: %w", err)
		}
		balances[accountID] = balance
	}
	if tracked[transfer.DebitAccountID] && balances[transfer.DebitAccountID] < transfer.Amount {
		return domain.Transfer{}, domain.ErrInsufficientFunds
	}

	row, err := queries.InsertTransfer(ctx, sqlcdb.InsertTransferParams{
		ExternalID:      transfer.ExternalID,
		DebitAccountID:  int32(transfer.DebitAccountID),
		CreditAccountID: int32(transfer.CreditAccountID),
		Amount:          transfer.Amount,
	})
	if err != nil {
		if isUniqueViolation(err) {
			return domain.Transfer{}, domain.ErrConflict
		}
		return domain.Transfer{}, fmt.Errorf("insert transfer: %w", err)
	}
	transfer = transferFromRow(row)

	entries := []sqlcdb.InsertEntryParams{
		{
			AccountID:  int32(transfer.DebitAccountID),
			TransferID: int32(transfer.ID),
			Amount:     transfer.Amount,
			Debit:      true,
		},
		{
			AccountID:  int32(transfer.CreditAccountID),
			TransferID: int32(transfer.ID),
			Amount:     transfer.Amount,
			Debit:      false,
		},
	}
	for _, entry := range entries {
		if err := queries.InsertEntry(ctx, entry); err != nil {
			return domain.Transfer{}, fmt.Errorf("insert transfer entry: %w", err)
		}
	}

	if tracked[transfer.DebitAccountID] {
		if err := insertBalance(ctx, queries, transfer.DebitAccountID, balances[transfer.DebitAccountID]-transfer.Amount); err != nil {
			return domain.Transfer{}, err
		}
	}
	if tracked[transfer.CreditAccountID] {
		if err := insertBalance(ctx, queries, transfer.CreditAccountID, balances[transfer.CreditAccountID]+transfer.Amount); err != nil {
			return domain.Transfer{}, err
		}
	}

	if err := tx.Commit(); err != nil {
		return domain.Transfer{}, fmt.Errorf("commit transfer: %w", err)
	}
	return transfer, nil
}

func (p *Postgres) ListAccountBalances(ctx context.Context) ([]domain.AccountBalance, error) {
	rows, err := p.queries.ListAccountBalances(ctx)
	if err != nil {
		return nil, fmt.Errorf("list account balances: %w", err)
	}
	balances := make([]domain.AccountBalance, 0, len(rows))
	for _, row := range rows {
		balances = append(balances, domain.AccountBalance{
			ID:             int64(row.ID),
			AccountID:      int64(row.AccountID),
			RunningBalance: row.RunningBalance,
			CreatedAt:      row.CreatedAt,
		})
	}
	return balances, nil
}

func accountFromRow(id int32, externalID string, trackBalance bool, createdAt time.Time, balance int64, hasBalanceSnapshot bool) (domain.Account, error) {
	if trackBalance && !hasBalanceSnapshot {
		return domain.Account{}, fmt.Errorf("tracked account %d has no balance snapshot", id)
	}
	account := domain.Account{
		ID:           int64(id),
		ExternalID:   externalID,
		TrackBalance: trackBalance,
		CreatedAt:    createdAt,
	}
	if trackBalance {
		value := balance
		account.CurrentBalance = &value
	}
	return account, nil
}

func transferFromRow(row sqlcdb.Transfer) domain.Transfer {
	return domain.Transfer{
		ID:              int64(row.ID),
		ExternalID:      row.ExternalID,
		DebitAccountID:  int64(row.DebitAccountID),
		CreditAccountID: int64(row.CreditAccountID),
		Amount:          row.Amount,
		CreatedAt:       row.CreatedAt,
	}
}

func insertBalance(ctx context.Context, queries *sqlcdb.Queries, accountID, balance int64) error {
	if err := queries.InsertAccountBalance(ctx, sqlcdb.InsertAccountBalanceParams{
		AccountID:      int32(accountID),
		RunningBalance: balance,
	}); err != nil {
		return fmt.Errorf("insert account balance snapshot: %w", err)
	}
	return nil
}

func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}
