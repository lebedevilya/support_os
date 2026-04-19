Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  root "home#index"

  mount Motor::Admin => "/admin", as: "motor_admin"

  resources :tickets, only: [ :index, :show ] do
    resource :trace, only: [ :show ], controller: "traces"
  end

  namespace :widget do
    resources :tickets, only: [ :new, :create ] do
      member do
        patch :close
      end
      resources :messages, only: [ :create ]
    end
  end
end
