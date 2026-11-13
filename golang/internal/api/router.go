package api

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"

	"accounting-service/internal/domain"
	"accounting-service/internal/service"

	"github.com/gin-gonic/gin"
)

type Handler struct {
	service *service.Service
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

func NewRouter(accountingService *service.Service) *gin.Engine {
	handler := &Handler{service: accountingService}
	router := gin.Default()

	router.GET("/healthz", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	v1 := router.Group("/api/v1")
	{
		v1.GET("/accounts", handler.listAccounts)
		v1.GET("/accounts/:id", handler.showAccount)
		v1.POST("/accounts", handler.createAccount)

		v1.GET("/transfers", handler.listTransfers)
		v1.GET("/transfers/:id", handler.showTransfer)
		v1.POST("/transfers", handler.createTransfer)

		v1.GET("/account_balances", handler.listAccountBalances)
	}

	return router
}

func (h *Handler) listAccounts(c *gin.Context) {
	accounts, err := h.service.ListAccounts(c.Request.Context())
	if err != nil {
		writeServiceError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"accounts": accounts})
}

func (h *Handler) showAccount(c *gin.Context) {
	id, err := parseID(c)
	if err != nil {
		writeServiceError(c, domain.ErrValidation)
		return
	}
	account, err := h.service.GetAccount(c.Request.Context(), id)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"account": account})
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
	account, err := h.service.CreateAccount(c.Request.Context(), service.CreateAccountInput{
		ExternalID:   payload.Account.ExternalID,
		TrackBalance: payload.Account.TrackBalance,
	})
	if err != nil {
		writeServiceError(c, err)
		return
	}
	c.JSON(http.StatusCreated, gin.H{"account": account})
}

func (h *Handler) listTransfers(c *gin.Context) {
	transfers, err := h.service.ListTransfers(c.Request.Context())
	if err != nil {
		writeServiceError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"transfers": transfers})
}

func (h *Handler) showTransfer(c *gin.Context) {
	id, err := parseID(c)
	if err != nil {
		writeServiceError(c, domain.ErrValidation)
		return
	}
	transfer, err := h.service.GetTransfer(c.Request.Context(), id)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"transfer": transfer})
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
	request := payload.Transfer
	transfer, err := h.service.CreateTransfer(c.Request.Context(), domain.Transfer{
		ExternalID:      request.ExternalID,
		DebitAccountID:  request.DebitAccountID,
		CreditAccountID: request.CreditAccountID,
		Amount:          request.Amount,
	})
	if err != nil {
		writeServiceError(c, err)
		return
	}
	c.JSON(http.StatusCreated, gin.H{"transfer": transfer})
}

func (h *Handler) listAccountBalances(c *gin.Context) {
	balances, err := h.service.ListAccountBalances(c.Request.Context())
	if err != nil {
		writeServiceError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"account_balances": balances})
}

func parseID(c *gin.Context) (int64, error) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id < 1 {
		return 0, domain.ErrValidation
	}
	return id, nil
}

func writeServiceError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, domain.ErrValidation):
		writeError(c, http.StatusUnprocessableEntity, "invalid input")
	case errors.Is(err, domain.ErrNotFound):
		writeError(c, http.StatusNotFound, "record not found")
	case errors.Is(err, domain.ErrConflict):
		writeError(c, http.StatusConflict, "external_id already exists")
	case errors.Is(err, domain.ErrInsufficientFunds):
		writeError(c, http.StatusUnprocessableEntity, "insufficient funds for debit account")
	default:
		log.Printf("request failed: %v", err)
		writeError(c, http.StatusInternalServerError, "internal server error")
	}
}

func writeError(c *gin.Context, status int, message string) {
	c.JSON(status, gin.H{"error": message})
}
