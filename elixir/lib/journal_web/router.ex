defmodule JournalWeb.Router do
  use JournalWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", JournalWeb do
    pipe_through :api
  end

  scope "/api/v1", JournalWeb do
    pipe_through :api

    get "/accounts", AccountController, :index
    post "/accounts", AccountController, :create
    get "/accounts/:id", AccountController, :show

    get "/transfers", TransferController, :index
    post "/transfers", TransferController, :create
    get "/transfers/:id", TransferController, :show

    get "/account_balances", AccountBalanceController, :index
  end
end
