package repository

import (
	"context"
	"database/sql"
	"errors"
	"fmt"

	"accounting-service/internal/domain"

	"github.com/jackc/pgx/v5/pgconn"
)

type Postgres struct {
	db *sql.DB
}

func NewPostgres(db *sql.DB) *Postgres {
	return &Postgres{db: db}
}

func (p *Postgres) ListAccounts(ctx context.Context) ([]domain.Account, error) {
	rows, err := p.db.QueryContext(ctx, `
		SELECT a.id, a.external_id, a.track_balance, a.created_at, b.running_balance
		FROM accounts a
		LEFT JOIN LATERAL (
			SELECT running_balance
			FROM account_balances
			WHERE account_id = a.id
			ORDER BY id DESC
			LIMIT 1
		) b ON TRUE
		ORDER BY a.id ASC`)
	if err != nil {
		return nil, fmt.Errorf("list accounts: %w", err)
	}
	defer rows.Close()

	accounts := make([]domain.Account, 0)
	for rows.Next() {
		account, err := scanAccount(rows)
		if err != nil {
			return nil, fmt.Errorf("scan account: %w", err)
		}
		accounts = append(accounts, account)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate accounts: %w", err)
	}
	return accounts, nil
}

func (p *Postgres) GetAccount(ctx context.Context, id int64) (domain.Account, error) {
	row := p.db.QueryRowContext(ctx, `
		SELECT a.id, a.external_id, a.track_balance, a.created_at, b.running_balance
		FROM accounts a
		LEFT JOIN LATERAL (
			SELECT running_balance
			FROM account_balances
			WHERE account_id = a.id
			ORDER BY id DESC
			LIMIT 1
		) b ON TRUE
		WHERE a.id = $1`, id)
	account, err := scanAccount(row)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.Account{}, domain.ErrNotFound
	}
	if err != nil {
		return domain.Account{}, fmt.Errorf("get account: %w", err)
	}
	return account, nil
}

func (p *Postgres) CreateAccount(ctx context.Context, externalID string, trackBalance bool) (domain.Account, error) {
	tx, err := p.db.BeginTx(ctx, nil)
	if err != nil {
		return domain.Account{}, fmt.Errorf("begin account creation: %w", err)
	}
	defer tx.Rollback()

	var account domain.Account
	account.ExternalID = externalID
	account.TrackBalance = trackBalance
	err = tx.QueryRowContext(ctx, `
		INSERT INTO accounts (external_id, track_balance)
		VALUES ($1, $2)
		RETURNING id, created_at`, externalID, trackBalance).Scan(&account.ID, &account.CreatedAt)
	if err != nil {
		if isUniqueViolation(err) {
			return domain.Account{}, domain.ErrConflict
		}
		return domain.Account{}, fmt.Errorf("insert account: %w", err)
	}

	if trackBalance {
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO account_balances (account_id, running_balance)
			VALUES ($1, 0)`, account.ID); err != nil {
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
	rows, err := p.db.QueryContext(ctx, `
		SELECT id, external_id, debit_account_id, credit_account_id, amount, created_at
		FROM transfers
		ORDER BY id ASC`)
	if err != nil {
		return nil, fmt.Errorf("list transfers: %w", err)
	}
	defer rows.Close()

	transfers := make([]domain.Transfer, 0)
	for rows.Next() {
		var transfer domain.Transfer
		if err := rows.Scan(
			&transfer.ID, &transfer.ExternalID, &transfer.DebitAccountID,
			&transfer.CreditAccountID, &transfer.Amount, &transfer.CreatedAt,
		); err != nil {
			return nil, fmt.Errorf("scan transfer: %w", err)
		}
		transfers = append(transfers, transfer)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate transfers: %w", err)
	}
	return transfers, nil
}

func (p *Postgres) GetTransfer(ctx context.Context, id int64) (domain.Transfer, error) {
	var transfer domain.Transfer
	err := p.db.QueryRowContext(ctx, `
		SELECT id, external_id, debit_account_id, credit_account_id, amount, created_at
		FROM transfers
		WHERE id = $1`, id).Scan(
		&transfer.ID, &transfer.ExternalID, &transfer.DebitAccountID,
		&transfer.CreditAccountID, &transfer.Amount, &transfer.CreatedAt,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.Transfer{}, domain.ErrNotFound
	}
	if err != nil {
		return domain.Transfer{}, fmt.Errorf("get transfer: %w", err)
	}
	return transfer, nil
}

func (p *Postgres) CreateTransfer(ctx context.Context, transfer domain.Transfer) (domain.Transfer, error) {
	tx, err := p.db.BeginTx(ctx, nil)
	if err != nil {
		return domain.Transfer{}, fmt.Errorf("begin transfer: %w", err)
	}
	defer tx.Rollback()

	rows, err := tx.QueryContext(ctx, `
		SELECT id, track_balance
		FROM accounts
		WHERE id IN ($1, $2)
		ORDER BY id
		FOR UPDATE`, transfer.DebitAccountID, transfer.CreditAccountID)
	if err != nil {
		return domain.Transfer{}, fmt.Errorf("lock transfer accounts: %w", err)
	}
	tracked := make(map[int64]bool, 2)
	for rows.Next() {
		var id int64
		var trackBalance bool
		if err := rows.Scan(&id, &trackBalance); err != nil {
			rows.Close()
			return domain.Transfer{}, fmt.Errorf("scan locked account: %w", err)
		}
		tracked[id] = trackBalance
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return domain.Transfer{}, fmt.Errorf("iterate locked accounts: %w", err)
	}
	if err := rows.Close(); err != nil {
		return domain.Transfer{}, fmt.Errorf("close locked accounts: %w", err)
	}
	if len(tracked) != 2 {
		return domain.Transfer{}, domain.ErrNotFound
	}

	balances := make(map[int64]int64, 2)
	for _, accountID := range []int64{transfer.DebitAccountID, transfer.CreditAccountID} {
		if !tracked[accountID] {
			continue
		}
		var balance int64
		err := tx.QueryRowContext(ctx, `
			SELECT running_balance
			FROM account_balances
			WHERE account_id = $1
			ORDER BY id DESC
			LIMIT 1`, accountID).Scan(&balance)
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

	err = tx.QueryRowContext(ctx, `
		INSERT INTO transfers (external_id, debit_account_id, credit_account_id, amount)
		VALUES ($1, $2, $3, $4)
		RETURNING id, created_at`,
		transfer.ExternalID, transfer.DebitAccountID, transfer.CreditAccountID, transfer.Amount,
	).Scan(&transfer.ID, &transfer.CreatedAt)
	if err != nil {
		if isUniqueViolation(err) {
			return domain.Transfer{}, domain.ErrConflict
		}
		return domain.Transfer{}, fmt.Errorf("insert transfer: %w", err)
	}

	entries := []struct {
		accountID int64
		debit     bool
	}{
		{accountID: transfer.DebitAccountID, debit: true},
		{accountID: transfer.CreditAccountID, debit: false},
	}
	for _, entry := range entries {
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO entries (account_id, transfer_id, amount, debit)
			VALUES ($1, $2, $3, $4)`,
			entry.accountID, transfer.ID, transfer.Amount, entry.debit,
		); err != nil {
			return domain.Transfer{}, fmt.Errorf("insert transfer entry: %w", err)
		}
	}

	if tracked[transfer.DebitAccountID] {
		if err := insertBalance(ctx, tx, transfer.DebitAccountID, balances[transfer.DebitAccountID]-transfer.Amount); err != nil {
			return domain.Transfer{}, err
		}
	}
	if tracked[transfer.CreditAccountID] {
		if err := insertBalance(ctx, tx, transfer.CreditAccountID, balances[transfer.CreditAccountID]+transfer.Amount); err != nil {
			return domain.Transfer{}, err
		}
	}

	if err := tx.Commit(); err != nil {
		return domain.Transfer{}, fmt.Errorf("commit transfer: %w", err)
	}
	return transfer, nil
}

func (p *Postgres) ListAccountBalances(ctx context.Context) ([]domain.AccountBalance, error) {
	rows, err := p.db.QueryContext(ctx, `
		SELECT id, account_id, running_balance, created_at
		FROM account_balances
		ORDER BY account_id ASC, id ASC`)
	if err != nil {
		return nil, fmt.Errorf("list account balances: %w", err)
	}
	defer rows.Close()

	balances := make([]domain.AccountBalance, 0)
	for rows.Next() {
		var balance domain.AccountBalance
		if err := rows.Scan(&balance.ID, &balance.AccountID, &balance.RunningBalance, &balance.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan account balance: %w", err)
		}
		balances = append(balances, balance)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate account balances: %w", err)
	}
	return balances, nil
}

type scanner interface {
	Scan(dest ...any) error
}

func scanAccount(row scanner) (domain.Account, error) {
	var account domain.Account
	var currentBalance sql.NullInt64
	if err := row.Scan(
		&account.ID, &account.ExternalID, &account.TrackBalance, &account.CreatedAt, &currentBalance,
	); err != nil {
		return domain.Account{}, err
	}
	if account.TrackBalance && currentBalance.Valid {
		account.CurrentBalance = &currentBalance.Int64
	}
	return account, nil
}

func insertBalance(ctx context.Context, tx *sql.Tx, accountID, balance int64) error {
	if _, err := tx.ExecContext(ctx, `
		INSERT INTO account_balances (account_id, running_balance)
		VALUES ($1, $2)`, accountID, balance); err != nil {
		return fmt.Errorf("insert account balance snapshot: %w", err)
	}
	return nil
}

func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}
