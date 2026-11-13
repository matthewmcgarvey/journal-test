package api

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

type Handler struct {
	db *sql.DB
}

type accountCreateRequest struct {
	ExternalID   string `json:"external_id"`
	TrackBalance *bool  `json:"track_balance"`
}

type transferCreateRequest struct {
	ExternalID      string `json:"external_id"`
	DebitAccountID  int64  `json:"debit_account_id"`
	CreditAccountID int64  `json:"credit_account_id"`
	Amount          int64  `json:"amount"`
}

type accountResponse struct {
	ID             int64     `json:"id"`
	ExternalID     string    `json:"external_id"`
	TrackBalance   bool      `json:"track_balance"`
	CurrentBalance *int64    `json:"current_balance"`
	CreatedAt      time.Time `json:"created_at"`
}

type transferResponse struct {
	ID              int64     `json:"id"`
	ExternalID      string    `json:"external_id"`
	DebitAccountID  int64     `json:"debit_account_id"`
	CreditAccountID int64     `json:"credit_account_id"`
	Amount          int64     `json:"amount"`
	CreatedAt       time.Time `json:"created_at"`
}

type balanceResponse struct {
	ID             int64     `json:"id"`
	AccountID      int64     `json:"account_id"`
	RunningBalance int64     `json:"running_balance"`
	CreatedAt      time.Time `json:"created_at"`
}

func NewRouter(db *sql.DB) *gin.Engine {
	h := &Handler{db: db}
	r := gin.Default()

	r.GET("/healthz", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	v1 := r.Group("/api/v1")
	{
		v1.GET("/accounts", h.listAccounts)
		v1.GET("/accounts/:id", h.showAccount)
		v1.POST("/accounts", h.createAccount)

		v1.GET("/transfers", h.listTransfers)
		v1.GET("/transfers/:id", h.showTransfer)
		v1.POST("/transfers", h.createTransfer)

		v1.GET("/account_balances", h.listAccountBalances)
	}

	return r
}

func (h *Handler) listAccounts(c *gin.Context) {
	rows, err := h.db.Query(`
		SELECT id, external_id, track_balance, created_at
		FROM accounts
		ORDER BY id ASC`,
	)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "failed to load accounts")
		return
	}
	defer rows.Close()

	accounts := make([]accountResponse, 0)
	for rows.Next() {
		var a accountResponse
		if err := rows.Scan(&a.ID, &a.ExternalID, &a.TrackBalance, &a.CreatedAt); err != nil {
			writeError(c, http.StatusInternalServerError, "failed to read account row")
			return
		}
		if a.TrackBalance {
			balance, err := h.latestBalanceForAccount(a.ID)
			if err != nil {
				writeError(c, http.StatusInternalServerError, "failed to load current balance")
				return
			}
			value := int64(balance)
			a.CurrentBalance = &value
		} else {
			a.CurrentBalance = nil
		}
		accounts = append(accounts, a)
	}
	if err := rows.Err(); err != nil {
		writeError(c, http.StatusInternalServerError, "failed to iterate accounts")
		return
	}
	c.JSON(http.StatusOK, gin.H{"accounts": accounts})
}

func (h *Handler) showAccount(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		writeError(c, http.StatusBadRequest, "invalid account id")
		return
	}

	var a accountResponse
	err = h.db.QueryRow(`
		SELECT id, external_id, track_balance, created_at
		FROM accounts
		WHERE id = $1`, id).Scan(&a.ID, &a.ExternalID, &a.TrackBalance, &a.CreatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(c, http.StatusNotFound, "account not found")
		return
	}
	if err != nil {
		writeError(c, http.StatusInternalServerError, "failed to load account")
		return
	}
	if a.TrackBalance {
		balance, err := h.latestBalanceForAccount(a.ID)
		if err != nil {
			writeError(c, http.StatusInternalServerError, "failed to load current balance")
			return
		}
		value := int64(balance)
		a.CurrentBalance = &value
	} else {
		a.CurrentBalance = nil
	}
	c.JSON(http.StatusOK, gin.H{"account": a})
}

func (h *Handler) createAccount(c *gin.Context) {
	var payload struct {
		Account *accountCreateRequest `json:"account"`
	}
	if err := json.NewDecoder(c.Request.Body).Decode(&payload); err != nil {
		writeError(c, http.StatusUnprocessableEntity, "invalid json payload")
		return
	}
	if payload.Account == nil {
		writeError(c, http.StatusBadRequest, "account object is required")
		return
	}
	account := payload.Account
	if strings.TrimSpace(account.ExternalID) == "" {
		writeError(c, http.StatusUnprocessableEntity, "external_id is required")
		return
	}
	trackBalance := true
	if account.TrackBalance != nil {
		trackBalance = *account.TrackBalance
	}
	if trackBalance {
		var existing int
		err := h.db.QueryRow(`SELECT 1 FROM accounts WHERE external_id = $1`, account.ExternalID).Scan(&existing)
		if err == nil {
			writeError(c, http.StatusConflict, "external_id already exists")
			return
		}
		if !errors.Is(err, sql.ErrNoRows) {
			writeError(c, http.StatusInternalServerError, "failed to check unique external_id")
			return
		}
	}

	var id int64
	var createdAt time.Time
	err := h.db.QueryRow(`
		INSERT INTO accounts (external_id, track_balance)
		VALUES ($1, $2)
		RETURNING id, created_at`, account.ExternalID, trackBalance).Scan(&id, &createdAt)
	if err != nil {
		if strings.Contains(err.Error(), "duplicate key") || strings.Contains(err.Error(), "unique constraint") {
			writeError(c, http.StatusConflict, "external_id already exists")
			return
		}
		writeError(c, http.StatusInternalServerError, "failed to create account")
		return
	}
	if trackBalance {
		if _, err := h.db.Exec(`INSERT INTO account_balances (account_id, running_balance) VALUES ($1, $2)`, id, 0); err != nil {
			writeError(c, http.StatusInternalServerError, "failed to create initial balance snapshot")
			return
		}
	}
	response := accountResponse{
		ID:           id,
		ExternalID:   account.ExternalID,
		TrackBalance: trackBalance,
		CreatedAt:    createdAt,
	}
	if trackBalance {
		zero := int64(0)
		response.CurrentBalance = &zero
	}
	c.JSON(http.StatusCreated, gin.H{"account": response})
}

func (h *Handler) listTransfers(c *gin.Context) {
	rows, err := h.db.Query(`
		SELECT id, external_id, debit_account_id, credit_account_id, amount, created_at
		FROM transfers
		ORDER BY id ASC`)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "failed to load transfers")
		return
	}
	defer rows.Close()

	transfers := make([]transferResponse, 0)
	for rows.Next() {
		var t transferResponse
		if err := rows.Scan(&t.ID, &t.ExternalID, &t.DebitAccountID, &t.CreditAccountID, &t.Amount, &t.CreatedAt); err != nil {
			writeError(c, http.StatusInternalServerError, "failed to read transfer row")
			return
		}
		transfers = append(transfers, t)
	}
	if err := rows.Err(); err != nil {
		writeError(c, http.StatusInternalServerError, "failed to iterate transfers")
		return
	}
	c.JSON(http.StatusOK, gin.H{"transfers": transfers})
}

func (h *Handler) showTransfer(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		writeError(c, http.StatusBadRequest, "invalid transfer id")
		return
	}
	var t transferResponse
	err = h.db.QueryRow(`
		SELECT id, external_id, debit_account_id, credit_account_id, amount, created_at
		FROM transfers
		WHERE id = $1`, id).Scan(&t.ID, &t.ExternalID, &t.DebitAccountID, &t.CreditAccountID, &t.Amount, &t.CreatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(c, http.StatusNotFound, "transfer not found")
		return
	}
	if err != nil {
		writeError(c, http.StatusInternalServerError, "failed to load transfer")
		return
	}
	c.JSON(http.StatusOK, gin.H{"transfer": t})
}

func (h *Handler) createTransfer(c *gin.Context) {
	var payload struct {
		Transfer *transferCreateRequest `json:"transfer"`
	}
	if err := json.NewDecoder(c.Request.Body).Decode(&payload); err != nil {
		writeError(c, http.StatusUnprocessableEntity, "invalid json payload")
		return
	}
	if payload.Transfer == nil {
		writeError(c, http.StatusBadRequest, "transfer object is required")
		return
	}
	tr := payload.Transfer
	if strings.TrimSpace(tr.ExternalID) == "" {
		writeError(c, http.StatusUnprocessableEntity, "external_id is required")
		return
	}
	if tr.DebitAccountID == 0 || tr.CreditAccountID == 0 {
		writeError(c, http.StatusUnprocessableEntity, "debit_account_id and credit_account_id are required")
		return
	}
	if tr.DebitAccountID == tr.CreditAccountID {
		writeError(c, http.StatusUnprocessableEntity, "debit_account_id and credit_account_id must be different")
		return
	}
	if tr.Amount <= 0 {
		writeError(c, http.StatusUnprocessableEntity, "amount must be a positive integer")
		return
	}

	ctx := c.Request.Context()
	tx, err := h.db.BeginTx(ctx, nil)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "failed to start transfer transaction")
		return
	}
	defer tx.Rollback()

	var debitAccount struct {
		ID           int64
		TrackBalance bool
	}
	var creditAccount struct {
		ID           int64
		TrackBalance bool
	}
	if err := tx.QueryRow(`SELECT id, track_balance FROM accounts WHERE id=$1`, tr.DebitAccountID).Scan(&debitAccount.ID, &debitAccount.TrackBalance); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(c, http.StatusNotFound, "debit account not found")
			return
		}
		writeError(c, http.StatusInternalServerError, "failed to load debit account")
		return
	}
	if err := tx.QueryRow(`SELECT id, track_balance FROM accounts WHERE id=$1`, tr.CreditAccountID).Scan(&creditAccount.ID, &creditAccount.TrackBalance); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(c, http.StatusNotFound, "credit account not found")
			return
		}
		writeError(c, http.StatusInternalServerError, "failed to load credit account")
		return
	}

	ids := []int64{tr.DebitAccountID, tr.CreditAccountID}
	for i := 0; i < len(ids); i++ {
		for j := i + 1; j < len(ids); j++ {
			if ids[i] > ids[j] {
				ids[i], ids[j] = ids[j], ids[i]
			}
		}
	}
	var lockedRows []int64
	locksQuery := `SELECT id FROM accounts WHERE id IN ($1, $2) ORDER BY id FOR UPDATE`
	rows, err := tx.Query(locksQuery, ids[0], ids[1])
	if err != nil {
		writeError(c, http.StatusInternalServerError, "failed to lock account rows")
		return
	}
	defer rows.Close()
	for rows.Next() {
		var rowID int64
		if err := rows.Scan(&rowID); err != nil {
			writeError(c, http.StatusInternalServerError, "failed to scan locked account rows")
			return
		}
		lockedRows = append(lockedRows, rowID)
	}
	if err := rows.Err(); err != nil {
		writeError(c, http.StatusInternalServerError, "failed to iterate locked account rows")
		return
	}
	if len(lockedRows) == 0 {
		writeError(c, http.StatusInternalServerError, "failed to lock affected accounts")
		return
	}

	balances := map[int64]int64{}
	for _, accountID := range []int64{tr.DebitAccountID, tr.CreditAccountID} {
		if !accountTracksBalance(tx, accountID) {
			continue
		}
		latest, err := latestBalanceForTx(tx, accountID)
		if err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				balances[accountID] = 0
				continue
			}
			writeError(c, http.StatusInternalServerError, "failed to load account balance snapshot")
			return
		}
		balances[accountID] = latest
	}
	if debitAccount.TrackBalance && balances[tr.DebitAccountID] < tr.Amount {
		writeError(c, http.StatusUnprocessableEntity, "insufficient funds for debit account")
		return
	}

	var transferID int64
	var createdAt time.Time
	err = tx.QueryRow(`
		INSERT INTO transfers (external_id, debit_account_id, credit_account_id, amount)
		VALUES ($1, $2, $3, $4)
		RETURNING id, created_at`, tr.ExternalID, tr.DebitAccountID, tr.CreditAccountID, tr.Amount).Scan(&transferID, &createdAt)
	if err != nil {
		if strings.Contains(err.Error(), "duplicate key") || strings.Contains(err.Error(), "unique constraint") {
			writeError(c, http.StatusConflict, "external_id already exists")
			return
		}
		writeError(c, http.StatusInternalServerError, "failed to create transfer")
		return
	}

	if _, err := tx.Exec(`INSERT INTO entries (account_id, transfer_id, amount, debit) VALUES ($1, $2, $3, true)`, tr.DebitAccountID, transferID, tr.Amount); err != nil {
		writeError(c, http.StatusInternalServerError, "failed to create debit entry")
		return
	}
	if _, err := tx.Exec(`INSERT INTO entries (account_id, transfer_id, amount, debit) VALUES ($1, $2, $3, false)`, tr.CreditAccountID, transferID, tr.Amount); err != nil {
		writeError(c, http.StatusInternalServerError, "failed to create credit entry")
		return
	}

	if debitAccount.TrackBalance {
		newBalance := balances[tr.DebitAccountID] - tr.Amount
		if _, err := tx.Exec(`INSERT INTO account_balances (account_id, running_balance) VALUES ($1, $2)`, tr.DebitAccountID, newBalance); err != nil {
			writeError(c, http.StatusInternalServerError, "failed to create debit account balance snapshot")
			return
		}
	}
	if creditAccount.TrackBalance {
		newBalance := balances[tr.CreditAccountID] + tr.Amount
		if _, err := tx.Exec(`INSERT INTO account_balances (account_id, running_balance) VALUES ($1, $2)`, tr.CreditAccountID, newBalance); err != nil {
			writeError(c, http.StatusInternalServerError, "failed to create credit account balance snapshot")
			return
		}
	}

	if err := tx.Commit(); err != nil {
		writeError(c, http.StatusInternalServerError, "failed to commit transfer")
		return
	}

	response := transferResponse{
		ID:              transferID,
		ExternalID:      tr.ExternalID,
		DebitAccountID:  tr.DebitAccountID,
		CreditAccountID: tr.CreditAccountID,
		Amount:          tr.Amount,
		CreatedAt:       createdAt,
	}
	c.JSON(http.StatusCreated, gin.H{"transfer": response})
}

func (h *Handler) listAccountBalances(c *gin.Context) {
	rows, err := h.db.Query(`
		SELECT id, account_id, running_balance, created_at
		FROM account_balances
		ORDER BY account_id ASC, id ASC`)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "failed to load account balances")
		return
	}
	defer rows.Close()

	balances := make([]balanceResponse, 0)
	for rows.Next() {
		var b balanceResponse
		if err := rows.Scan(&b.ID, &b.AccountID, &b.RunningBalance, &b.CreatedAt); err != nil {
			writeError(c, http.StatusInternalServerError, "failed to read balance row")
			return
		}
		balances = append(balances, b)
	}
	if err := rows.Err(); err != nil {
		writeError(c, http.StatusInternalServerError, "failed to iterate balances")
		return
	}
	c.JSON(http.StatusOK, gin.H{"account_balances": balances})
}

func (h *Handler) latestBalanceForAccount(accountID int64) (int64, error) {
	var runningBalance int64
	err := h.db.QueryRow(`
		SELECT running_balance
		FROM account_balances
		WHERE account_id = $1
		ORDER BY id DESC
		LIMIT 1`, accountID).Scan(&runningBalance)
	if err != nil {
		return 0, err
	}
	return runningBalance, nil
}

func latestBalanceForTx(tx *sql.Tx, accountID int64) (int64, error) {
	var runningBalance int64
	err := tx.QueryRow(`
		SELECT running_balance
		FROM account_balances
		WHERE account_id = $1
		ORDER BY id DESC
		LIMIT 1`, accountID).Scan(&runningBalance)
	if err != nil {
		return 0, err
	}
	return runningBalance, nil
}

func accountTracksBalance(tx *sql.Tx, accountID int64) bool {
	var tracked bool
	err := tx.QueryRow(`SELECT track_balance FROM accounts WHERE id = $1`, accountID).Scan(&tracked)
	if err != nil {
		return false
	}
	return tracked
}

func writeError(c *gin.Context, status int, message string) {
	c.JSON(status, gin.H{"error": message})
}

func init() {
	_ = fmt.Sprintf
	_ = strings.TrimSpace
	_ = strconv.ParseInt
}
