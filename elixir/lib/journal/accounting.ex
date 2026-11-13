defmodule Journal.Accounting do
  import Ecto.Query

  alias Journal.Accounting.{Account, AccountBalance, Entry, Transfer}
  alias Journal.Repo

  def list_accounts do
    accounts_with_balances_query()
    |> order_by([account, _latest, _balance], asc: account.id)
    |> Repo.all()
    |> Enum.map(fn {account, balance} -> %{account: account, current_balance: balance} end)
  end

  def get_account(id) do
    case accounts_with_balances_query()
         |> where([account, _latest, _balance], account.id == ^id)
         |> Repo.one() do
      {account, balance} -> %{account: account, current_balance: balance}
      nil -> nil
    end
  end

  def create_account(attrs) do
    changeset = Account.changeset(%Account{}, attrs)

    if changeset.valid? do
      Repo.transaction(fn ->
        case Repo.insert(changeset) do
          {:ok, account} ->
            if account.track_balance do
              case Repo.insert(
                     AccountBalance.changeset(%AccountBalance{}, %{
                       account_id: account.id,
                       running_balance: 0
                     })
                   ) do
                {:ok, _balance} -> account
                {:error, balance_changeset} -> Repo.rollback({:changeset, balance_changeset})
              end
            else
              account
            end

          {:error, account_changeset} ->
            Repo.rollback({:changeset, account_changeset})
        end
      end)
      |> unwrap_transaction()
    else
      {:error, changeset}
    end
  end

  def list_transfers do
    Transfer
    |> order_by(asc: :id)
    |> Repo.all()
  end

  def get_transfer(id), do: Repo.get(Transfer, id)

  def list_account_balances(account_id \\ nil) do
    query = from(balance in AccountBalance, order_by: [asc: balance.id])

    query =
      if account_id, do: where(query, [balance], balance.account_id == ^account_id), else: query

    Repo.all(query)
  end

  def create_transfer(attrs) do
    changeset = Transfer.changeset(%Transfer{}, attrs)

    if changeset.valid? do
      transfer = Ecto.Changeset.apply_changes(changeset)

      Repo.transaction(fn ->
        accounts = lock_accounts([transfer.debit_account_id, transfer.credit_account_id])

        if length(accounts) != 2 do
          Repo.rollback(:invalid_account)
        end

        debit_account = Enum.find(accounts, &(&1.id == transfer.debit_account_id))
        credit_account = Enum.find(accounts, &(&1.id == transfer.credit_account_id))
        debit_balance = latest_balance(debit_account.id) || 0

        if debit_account.track_balance and debit_balance < transfer.amount do
          Repo.rollback(:insufficient_funds)
        end

        inserted_transfer =
          case Repo.insert(changeset) do
            {:ok, inserted} -> inserted
            {:error, transfer_changeset} -> Repo.rollback({:changeset, transfer_changeset})
          end

        create_entry!(debit_account.id, inserted_transfer.id, inserted_transfer.amount, true)
        create_entry!(credit_account.id, inserted_transfer.id, inserted_transfer.amount, false)

        if debit_account.track_balance do
          create_balance!(debit_account.id, debit_balance - inserted_transfer.amount)
        end

        if credit_account.track_balance do
          credit_balance = latest_balance(credit_account.id) || 0
          create_balance!(credit_account.id, credit_balance + inserted_transfer.amount)
        end

        inserted_transfer
      end)
      |> unwrap_transaction()
    else
      {:error, changeset}
    end
  end

  defp accounts_with_balances_query do
    latest_balances =
      from(balance in AccountBalance,
        group_by: balance.account_id,
        select: %{account_id: balance.account_id, id: max(balance.id)}
      )

    from(account in Account,
      left_join: latest in subquery(latest_balances),
      on: latest.account_id == account.id,
      left_join: balance in AccountBalance,
      on: balance.id == latest.id,
      select: {account, balance.running_balance}
    )
  end

  defp lock_accounts(account_ids) do
    from(account in Account,
      where: account.id in ^Enum.sort(account_ids),
      order_by: [asc: account.id],
      lock: "FOR UPDATE"
    )
    |> Repo.all()
  end

  defp latest_balance(account_id) do
    Repo.one(
      from(balance in AccountBalance,
        where: balance.account_id == ^account_id,
        order_by: [desc: balance.id],
        limit: 1,
        select: balance.running_balance
      )
    )
  end

  defp create_entry!(account_id, transfer_id, amount, debit) do
    attrs = %{account_id: account_id, transfer_id: transfer_id, amount: amount, debit: debit}

    case Repo.insert(Entry.changeset(%Entry{}, attrs)) do
      {:ok, entry} -> entry
      {:error, changeset} -> Repo.rollback({:changeset, changeset})
    end
  end

  defp create_balance!(account_id, running_balance) do
    attrs = %{account_id: account_id, running_balance: running_balance}

    case Repo.insert(AccountBalance.changeset(%AccountBalance{}, attrs)) do
      {:ok, balance} -> balance
      {:error, changeset} -> Repo.rollback({:changeset, changeset})
    end
  end

  defp unwrap_transaction({:ok, result}), do: {:ok, result}
  defp unwrap_transaction({:error, {:changeset, changeset}}), do: {:error, changeset}
  defp unwrap_transaction({:error, reason}), do: {:error, reason}
end
