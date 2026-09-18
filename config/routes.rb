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

    # `only:` spelled out because this is an `api_only` app, where a bare
    # `resources` SILENTLY OMITS `new` and `edit` — there are no forms in an
    # API. Administrate is all forms, so the console's "Edit merchant" button
    # pointed at a route that did not exist and 404'd, which is how a merchant's
    # commission rate became uneditable without a deploy. Every other resource
    # here already listed its actions and was unaffected.
    resources :merchants, only: %i[index show new create edit update destroy] do
      member do
        patch :open_merchant
        patch :close_merchant
        patch :approve
        patch :suspend
        # UNDO. One-way door 6 makes a delete recoverable in the DATA; without
        # this the recovery needs a developer and a Rails console.
        patch :restore
      end
    end

    resources :courier_profiles, only: %i[index show edit update] do
      member do
        patch :approve
        # The asking path, which is not a refusal — see the controller.
        patch :ask_for_more
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

    # Opening hours had no route at all, so a shop's hours could be neither seen
    # nor set — and `opening_hours` has been serialized to customers the whole
    # time, returning [] for 201 of 205 merchants. Admin onboards restaurants
    # (PRODUCT.md), so this is the only place they can come from.
    resources :merchant_opening_hours, only: %i[index show new create edit update destroy]

    # MENU MANAGEMENT. Phase 1 of PRODUCT.md is the console because "you cannot
    # test an order without a restaurant and a menu", and :66 makes admin the
    # party that onboards. Until these existed a menu could only arrive from a
    # seed, so the first real restaurant could not be onboarded at all.
    # The browse taxonomy. `public/merchants_controller:15` already filters on
    # it, and nothing could assign a merchant to one.
    resources :merchant_categories, only: %i[index show new create edit update destroy]

    resources :catalog_categories, only: %i[index show new create edit update destroy]
    resources :catalog_items, only: %i[index show new create edit update destroy]

    resources :users, only: %i[index show edit update] do
      member do
        patch :suspend
        patch :reinstate
        patch :restore
      end
    end

    # The Config screen. Editable with no deploy is the whole point.
    resources :settings, only: %i[index show edit update]

    # The per-vehicle tariffs, for the same reason. `only:` spelled out because
    # this is an `api_only` app, where a bare `resources` omits `new` and
    # `edit` — see the merchants block above for what that cost.
    resources :pricing_rates, only: %i[index show new create edit update]

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
        # SIGN-UP IS ITS OWN ENDPOINT NOW. Under OTP it was the same action as
        # signing in, because holding the phone was the proof. With a password
        # it cannot be: one needs the account to exist and the other needs it
        # not to.
        post "registration", to: "registrations#create"
        post "session", to: "sessions#create"
        delete "session", to: "sessions#destroy"
        # FORGOTTEN PASSWORD, in two steps. `post` asks for a code and `put`
        # spends it — one resource, not two endpoints called "request" and
        # "confirm". Singular because it is one person's one reset.
        post "password_reset", to: "password_resets#create"
        put "password_reset", to: "password_resets#update"
      end

      # Guest-browsable. Deliberately not under a role namespace, because it
      # belongs to nobody in particular — a user who has not logged in yet.
      namespace :public do
        resources :merchants, only: %i[index show] do
          get :catalog, on: :member
        end
        resources :merchant_categories, only: :index
        # Needed by the SHOP APPLICATION form, which is reached by somebody who
        # holds no merchant role — that is what they are applying for. A
        # taxonomy anybody can see by browsing is not sensitive.
        resources :merchant_kinds, only: :index

        # The settings a CLIENT may know, before anyone logs in. Singular: it
        # is one small object, not a collection to page through.
        resource :app_config, only: :show, controller: "app_config"
      end

      # THE TWO PARTNER FRONT DOORS. Neither is role-namespaced, because an
      # applicant holds no partner role yet — that is what they are asking for.
      # Courier registration is `courier/registration`, since it belongs to a
      # courier profile; a shop's application IS a `merchants` row in its `lead`
      # state, so its door is here.
      resource :merchant_application, only: %i[show create], controller: "merchant_applications"

      # Namespaced by ROLE. Three thin controllers beat one fat one branching
      # on current_user — duplication between roles is cheaper than coupling
      # between roles, because roles diverge and the conditionals never get
      # removed.
      # The signed-in person. Not under a role namespace: unlike an order,
      # these mean the same thing to all four roles.
      # THE DRAWN LINE, by road. Not role-namespaced for the same reason `me`
      # is not: one map screen serves customer, courier and merchant, and the
      # question means the same thing to all three.
      resource :route, only: %i[show], controller: "routes"

      resource :me, only: %i[show update destroy], controller: "me" do
        post :switch_role
        post :register_device
        delete :unregister_device
        # Setting it is a PATCH to `me` like any other profile field; removing
        # it is its own verb, because it must be as easy as setting it.
        delete :avatar, action: :destroy_avatar
      end

      namespace :couriers, path: "courier" do
        # APPLYING. Deliberately NOT behind the approved-courier gate the rest
        # of this namespace sits behind — an applicant has no approved profile
        # and no wallet, so that gate would lock out exactly the people who
        # need this. Its controller inherits Api::V1::BaseController directly.
        resource :registration, only: %i[show create update], controller: "registrations"

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

        # Singular: one courier, one wallet.
        resource :wallet, only: :show, controller: "wallet" do
          get :entries
          get :settlements
        end

        # The one job in front of them, not a list.
        resource :job, only: :show, controller: "jobs"
        # `kind` is in the path because the two demand types are separate
        # tables — one screen does not mean one table.
        post "jobs/:kind/:id/advance", to: "jobs#advance", as: :advance_job
        post "jobs/:kind/:id/problem", to: "jobs#problem", as: :problem_job
        # "I am at the gate" — its own action rather than a step, because it
        # moves nothing: what changes is that the customer is told.
        post "jobs/:kind/:id/arrived", to: "jobs#arrived", as: :arrived_job
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
            # `preparing` is not ceremony. Order::TRANSITIONS goes
            # accepted → preparing → ready, so without this route the board
            # dead-ended at `accepted`: the Ready button answered 422
            # `invalid_transition` and there was no way forward. Collapsing the
            # two into one call was the alternative and it is worse — both
            # transitions would carry the same timestamp, and "how long do
            # orders sit in preparing" is the metric that runs a delivery
            # business and cannot be backfilled.
            post :preparing
            post :ready
          end
        end
      end

      namespace :customers, path: "customer" do
        # Saved pins. A pin, a voice note and a phone number — never a typed
        # street address.
        resources :addresses, only: %i[index create update destroy] do
          post :make_default, on: :member
        end

        resources :orders, only: %i[index show create] do
          post :quote, on: :collection
          post :cancel, on: :member
          # Where the order is, for the map. Its own endpoint because it is the
          # one payload polled while a courier moves, and because it must
          # refuse a TERMINAL order — which a field on the order serializer
          # could not.
          get :track, on: :member
        end
      end
    end
  end
end
