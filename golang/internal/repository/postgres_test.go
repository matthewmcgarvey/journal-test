package repository

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"testing"
	"time"

	"accounting-service/internal/domain"

	_ "github.com/jackc/pgx/v5/stdlib"
)

func TestPostgresTransferCreatesEntriesAndBalanceSnapshotsAtomically(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set TEST_DATABASE_URL to run PostgreSQL integration tests")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	db, err := sql.Open("pgx", dsn)
	if err != nil {
		t.Fatalf("open PostgreSQL connection: %v", err)
	}
	t.Cleanup(func() {
		if err := db.Close(); err != nil {
			t.Errorf("close PostgreSQL connection: %v", err)
		}
	})
	if err := db.PingContext(ctx); err != nil {
		t.Fatalf("ping PostgreSQL: %v", err)
	}

	repository := NewPostgres(db)
	testID := fmt.Sprintf("integration-test-%d", time.Now().UnixNano())
	createdAccountIDs := make([]int64, 0, 3)
	createdTransferIDs := make([]int64, 0, 2)
	t.Cleanup(func() {
		cleanupCtx, cleanupCancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cleanupCancel()

		for _, transferID := range createdTransferIDs {
			if _, err := db.ExecContext(cleanupCtx, `DELETE FROM entries WHERE transfer_id = $1`, transferID); err != nil {
				t.Errorf("delete test entries for transfer %d: %v", transferID, err)
			}
			if _, err := db.ExecContext(cleanupCtx, `DELETE FROM transfers WHERE id = $1`, transferID); err != nil {
				t.Errorf("delete test transfer %d: %v", transferID, err)
			}
		}
		for _, accountID := range createdAccountIDs {
			if _, err := db.ExecContext(cleanupCtx, `DELETE FROM entries WHERE account_id = $1`, accountID); err != nil {
				t.Errorf("delete test entries for account %d: %v", accountID, err)
			}
			if _, err := db.ExecContext(cleanupCtx, `DELETE FROM account_balances WHERE account_id = $1`, accountID); err != nil {
				t.Errorf("delete test balance snapshots for account %d: %v", accountID, err)
			}
			if _, err := db.ExecContext(cleanupCtx, `DELETE FROM accounts WHERE id = $1`, accountID); err != nil {
				t.Errorf("delete test account %d: %v", accountID, err)
			}
		}
	})

	source, err := repository.CreateAccount(ctx, testID+"-source", false)
	if err != nil {
		t.Fatalf("create untracked source account: %v", err)
	}
	createdAccountIDs = append(createdAccountIDs, source.ID)

	debit, err := repository.CreateAccount(ctx, testID+"-debit", true)
	if err != nil {
		t.Fatalf("create tracked debit account: %v", err)
	}
	createdAccountIDs = append(createdAccountIDs, debit.ID)

	credit, err := repository.CreateAccount(ctx, testID+"-credit", true)
	if err != nil {
		t.Fatalf("create tracked credit account: %v", err)
	}
	createdAccountIDs = append(createdAccountIDs, credit.ID)

	funding, err := repository.CreateTransfer(ctx, domain.Transfer{
		ExternalID:      testID + "-funding",
		DebitAccountID:  source.ID,
		CreditAccountID: debit.ID,
		Amount:          100,
	})
	if err != nil {
		t.Fatalf("create funding transfer: %v", err)
	}
	createdTransferIDs = append(createdTransferIDs, funding.ID)

	transfer, err := repository.CreateTransfer(ctx, domain.Transfer{
		ExternalID:      testID + "-transfer",
		DebitAccountID:  debit.ID,
		CreditAccountID: credit.ID,
		Amount:          75,
	})
	if err != nil {
		t.Fatalf("create transfer: %v", err)
	}
	createdTransferIDs = append(createdTransferIDs, transfer.ID)

	debit, err = repository.GetAccount(ctx, debit.ID)
	if err != nil {
		t.Fatalf("get debit account: %v", err)
	}
	credit, err = repository.GetAccount(ctx, credit.ID)
	if err != nil {
		t.Fatalf("get credit account: %v", err)
	}
	if debit.CurrentBalance == nil || *debit.CurrentBalance != 25 {
		t.Fatalf("debit current balance = %v, want 25", debit.CurrentBalance)
	}
	if credit.CurrentBalance == nil || *credit.CurrentBalance != 75 {
		t.Fatalf("credit current balance = %v, want 75", credit.CurrentBalance)
	}
	source, err = repository.GetAccount(ctx, source.ID)
	if err != nil {
		t.Fatalf("get untracked source account: %v", err)
	}
	if source.CurrentBalance != nil {
		t.Fatalf("untracked account current balance = %v, want nil", source.CurrentBalance)
	}

	var validEntryCount int
	if err := db.QueryRowContext(ctx, `
		SELECT COUNT(*)
		FROM entries
		WHERE transfer_id = $1
		  AND amount = 75
		  AND ((account_id = $2 AND debit = TRUE) OR (account_id = $3 AND debit = FALSE))`,
		transfer.ID, debit.ID, credit.ID,
	).Scan(&validEntryCount); err != nil {
		t.Fatalf("count transfer entries: %v", err)
	}
	if validEntryCount != 2 {
		t.Fatalf("valid debit/credit entry count = %d, want 2", validEntryCount)
	}
	var debitSnapshotCount, creditSnapshotCount int
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM account_balances WHERE account_id = $1`, debit.ID).Scan(&debitSnapshotCount); err != nil {
		t.Fatalf("count debit account snapshots: %v", err)
	}
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM account_balances WHERE account_id = $1`, credit.ID).Scan(&creditSnapshotCount); err != nil {
		t.Fatalf("count credit account snapshots: %v", err)
	}
	if debitSnapshotCount != 3 || creditSnapshotCount != 2 {
		t.Fatalf("snapshot counts = (%d, %d), want (3, 2)", debitSnapshotCount, creditSnapshotCount)
	}
	var sourceSnapshotCount int
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM account_balances WHERE account_id = $1`, source.ID).Scan(&sourceSnapshotCount); err != nil {
		t.Fatalf("count untracked account snapshots: %v", err)
	}
	if sourceSnapshotCount != 0 {
		t.Fatalf("untracked account has %d snapshots, want 0", sourceSnapshotCount)
	}

	_, err = repository.CreateTransfer(ctx, domain.Transfer{
		ExternalID:      testID + "-insufficient",
		DebitAccountID:  debit.ID,
		CreditAccountID: credit.ID,
		Amount:          26,
	})
	if !errors.Is(err, domain.ErrInsufficientFunds) {
		t.Fatalf("insufficient transfer error = %v, want ErrInsufficientFunds", err)
	}

	var rejectedTransferCount, rejectedEntryCount int
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM transfers WHERE external_id = $1`, testID+"-insufficient").Scan(&rejectedTransferCount); err != nil {
		t.Fatalf("count rejected transfers: %v", err)
	}
	if err := db.QueryRowContext(ctx, `
		SELECT COUNT(*)
		FROM entries e JOIN transfers t ON t.id = e.transfer_id
		WHERE t.external_id = $1`, testID+"-insufficient").Scan(&rejectedEntryCount); err != nil {
		t.Fatalf("count rejected entries: %v", err)
	}
	if rejectedTransferCount != 0 || rejectedEntryCount != 0 {
		t.Fatalf("rejected transfer persisted %d transfer rows and %d entries", rejectedTransferCount, rejectedEntryCount)
	}
	debit, err = repository.GetAccount(ctx, debit.ID)
	if err != nil {
		t.Fatalf("get debit account after rejected transfer: %v", err)
	}
	if debit.CurrentBalance == nil || *debit.CurrentBalance != 25 {
		t.Fatalf("debit current balance after rejection = %v, want 25", debit.CurrentBalance)
	}
}
