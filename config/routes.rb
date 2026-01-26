Rails.application.routes.draw do
  root "home#index"

  get "/sign_in", to: "sessions#new"
  post "/sign_in", to: "sessions#create"
  delete "/logout", to: "sessions#destroy"

  namespace :admin do
    root to: "dashboard#index"

    resources :branch_targets, only: %i[index edit update]
    resources :candidate_bumps, only: %i[index show update]
    resources :advisories, only: %i[index show]
    resources :pull_requests, only: %i[index show]
    resources :system_events, only: %i[index show]
    resource :settings, only: %i[show edit update]
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
