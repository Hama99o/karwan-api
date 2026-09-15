Rails.application.routes.draw do
  # Health check, used by Kamal and by the load balancer.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      # Authentication. Public by necessity — there is nobody to authenticate
      # yet — and throttled because SMS costs real money.
      namespace :auth do
        post "otp", to: "otp#create"
        post "session", to: "sessions#create"
        delete "session", to: "sessions#destroy"
      end

      # Guest-browsable. Deliberately not under a role namespace, because it
      # belongs to nobody in particular — a user who has not logged in yet.
      namespace :public do
        resources :merchants, only: %i[index show] do
          get :catalog, on: :member
        end
        resources :merchant_categories, only: :index
      end
    end
  end
end
