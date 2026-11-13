package domain

type Account struct {
	ID           int64  `json:"id"`
	ExternalID   string `json:"external_id"`
	TrackBalance bool   `json:"track_balance"`
	CreatedAt    string `json:"created_at"`
	CurrentBalance *int64 `json:"current_balance,omitempty"`
}

type Transfer struct {
	ID              int64  `json:"id"`
	ExternalID      string `json:"external_id"`
	DebitAccountID  int64  `json:"debit_account_id"`
	CreditAccountID int64  `json:"credit_account_id"`
	Amount          int64  `json:"amount"`
	CreatedAt       string `json:"created_at"`
}

type AccountBalance struct {
	ID            int64  `json:"id"`
	AccountID     int64  `json:"account_id"`
	RunningBalance int64 `json:"running_balance"`
	CreatedAt     string `json:"created_at"`
}
