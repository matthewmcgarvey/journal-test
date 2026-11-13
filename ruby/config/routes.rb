Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resources :accounts, only: %i[index show create]
      resources :transfers, only: %i[index show create]
      resources :account_balances, only: %i[index]
    end
  end
end
