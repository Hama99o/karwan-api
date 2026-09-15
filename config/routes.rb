Rails.application.routes.draw do
  # ---- The ops console --------------------------------------------------
  #
  # Administrate, inside this repo rather than a second app. Browser sessions
  # and a password, NOT the mobile phone+OTP auth: this is a human at a desk
  # with power to cancel any order and credit any wallet, and AdminUser is a
  # separate table so a customer token can never reach it.
  devise_for :admin_users, skip: %i[registrations sessions], path: "admin"
  # No public registration route, ever — admin accounts are created out of band.
  as :admin_user do
    get "admin/login", to: "admin/sessions#new", as: :new_admin_user_session
    post "admin/login", to: "admin/sessions#create", as: :admin_user_session
    delete "admin/logout", to: "admin/sessions#destroy", as: :destroy_admin_user_session
  end

  namespace :admin do
    # THE INTERVENTIONS ARE THE POINT. A default Administrate install gives a
    # CRUD form; what makes a delivery business operable is being able to
    # reassign a courier or mark an order failed, each one logged with who did
    # it — which a generic form edit could never record.
    resources :orders, only: %i[index show] do
      member do
        patch :reassign
        patch :cancel
        patch :fail
        patch :redispatch
      end
    end

    resources :trips, only: %i[index show]

    resources :merchants do
      member do
        patch :open_merchant
        patch :close_merchant
        patch :approve
        patch :suspend
      end
    end

    resources :courier_profiles, only: %i[index show edit update] do
      member do
        patch :approve
        patch :reject
        patch :take_off_shift
      end
    end

    resources :courier_wallets, only: %i[index show edit update] do
      member do
        post :top_up
        post :adjust
        post :reimburse
        post :settle
      end
    end

    resources :users, only: %i[index show edit update] do
      member do
        patch :suspend
        patch :reinstate
      end
    end

    # The Config screen. Editable with no deploy is the whole point.
    resources :settings, only: %i[index show edit update]

    # Read-only by design: an editable audit log is not an audit log, and a
    # ledger whose entries can be rewritten cannot be reconciled.
    resources :audit_logs, only: %i[index show]
    resources :wallet_entries, only: %i[index show]
    resources :settlements, only: %i[index show]

    root to: "dashboard#index"
  end

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
        # The open/closed toggle and the sold-out toggle are their own routes
        # rather than fields on an update form. Both are used in a hurry —
        # PRODUCT.md calls the sold-out one "one tap from the order board" —
        # and a form that could fail validation for an unrelated reason must
        # not be able to leave a shop marked open that isn't.
        resource :profile, only: :show, controller: "profiles" do
          post :open_now
          post :close_now
        end

        resources :catalog_categories, only: %i[create update destroy]
        resources :catalog_items, only: %i[index create update destroy] do
          member do
            post :sold_out
            post :available
          end
        end

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
