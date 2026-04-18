Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  root "home#index"

  authenticate_or_request_with_http_basic do |username, password|
    username == "admin" && password == "password"
  end do
    mount Motor::Admin => '/admin'
  end

  resources :tickets, only: [ :index, :show ] do
    resource :trace, only: [ :show ], controller: "traces"
  end

  namespace :widget do
    resources :tickets, only: [ :new, :create ] do
      resources :messages, only: [ :create ]
    end
  end
end
