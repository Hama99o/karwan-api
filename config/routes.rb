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

      # Namespaced by ROLE. Three thin controllers beat one fat one branching
      # on current_user — duplication between roles is cheaper than coupling
      # between roles, because roles diverge and the conditionals never get
      # removed.
      namespace :couriers, path: "courier" do
        # Singular: a courier has one shift state, so it is a resource rather
        # than a collection.
        resource :shift, only: %i[show update], controller: "shifts" do
          post :location, on: :member
        end

        # Singular on purpose: a courier has at most ONE live offer, and an
        # index route would invite a list screen the product deliberately does
        # not have.
        resource :offer, only: :show, controller: "offers"
        resources :offers, only: [] do
          member do
            post :accept
            post :decline
          end
        end

        # The one job in front of them, not a list.
        resource :job, only: :show, controller: "jobs"
        # `kind` is in the path because the two demand types are separate
        # tables — one screen does not mean one table.
        post "jobs/:kind/:id/advance", to: "jobs#advance", as: :advance_job
        post "jobs/:kind/:id/problem", to: "jobs#problem", as: :problem_job
      end

      namespace :merchants, path: "merchant" do
        resources :orders, only: %i[index show] do
          member do
            post :accept
            post :reject
            post :ready
          end
        end
      end

      namespace :customers, path: "customer" do
        resources :orders, only: %i[index show create] do
          post :quote, on: :collection
          post :cancel, on: :member
        end
      end
    end
  end
end
