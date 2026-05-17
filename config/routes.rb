Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  mount ActionCable.server => "/cable"
  root "home#index"

  mount Motor::Admin => "/admin", as: "motor_admin"

  resources :companies, only: [ :show ], param: :slug

  namespace :webhooks do
    post "github/pull_request", to: "github_pull_requests#create"
  end

  resources :tickets, only: [ :index, :show ] do
    post :reply, on: :member
    resource :trace, only: [ :show ], controller: "traces"
  end

  namespace :widget do
    resources :tickets, only: [ :new, :create ] do
      member do
        patch :close
        patch :handoff
        get :chat
      end
      resources :messages, only: [ :create ]
    end

    # used for regression sweeps
    namespace :test_api do
      resources :tickets, only: [ :create, :show ] do
        member do
          post :close
          post :messages, action: :create_message
        end
      end
    end
  end
end
