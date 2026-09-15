module Customers
  # A merchant as a CUSTOMER sees it. Photo-led and thin, because this renders
  # in a list on a cheap phone over a metered connection.
  #
  # Deliberately omits everything operational: the owner's name and tazkira, the
  # commission rate, the licence number, the verifier. A customer has no
  # business seeing any of it, and a serializer that carried it "for later" is
  # how it leaks.
  class MerchantSerializer < ApplicationSerializer
    identifier :id

    fields :name, :is_open

    field :kind do |merchant|
      merchant.merchant_kind&.slug
    end

    # AFGHAN_UX.md: photos of the actual food, large, on every item. A large
    # share of users cannot read fluently, so the photo IS the label and a text
    # row is a literacy tax.
    field :logo_url do |merchant|
      merchant.logo.attached? ? Rails.application.routes.url_helpers.rails_blob_path(merchant.logo, only_path: true) : nil
    end

    field :storefront_photo_url do |merchant|
      if merchant.storefront_photo.attached?
        Rails.application.routes.url_helpers.rails_blob_path(merchant.storefront_photo, only_path: true)
      end
    end

    view :list do
      # Localised by the SERVER from the caller's locale, so the client does not
      # have to hold a translation table for seeded taxonomy.
      field :kind_name do |merchant, options|
        merchant.merchant_kind&.name_for(options[:locale] || "fa")
      end

      field :categories do |merchant, options|
        merchant.merchant_categories.map { |category| category.name_for(options[:locale] || "fa") }
      end

      field :prep_time_minutes do |merchant|
        merchant.effective_prep_time_minutes
      end

      # Straight-line distance and a minute figure, both computed server-side.
      # Never assembled on the client: a client that computes its own distance
      # will disagree with the fee the server charged.
      field :distance_km do |merchant, options|
        next nil if options[:from].blank?

        Geo::Distance.km(from_lat: options[:from][0], from_lng: options[:from][1],
                         to_lat: merchant.latitude, to_lng: merchant.longitude)
      end

      field :eta_minutes do |merchant, options|
        next nil if options[:from].blank?

        km = Geo::Distance.km(from_lat: options[:from][0], from_lng: options[:from][1],
                              to_lat: merchant.latitude, to_lng: merchant.longitude)
        travel = Geo::Distance.travel_minutes(km)
        next nil if travel.nil?

        travel + (merchant.effective_prep_time_minutes || 0)
      end

      # A closed merchant is SHOWN, not hidden — greyed, with when it opens
      # again. Hiding it makes the app look empty at 7am.
      field :accepting_orders do |merchant|
        merchant.accepting_orders?
      end
    end

    view :detailed do
      include_view :list

      fields :landmark_note, :phone

      field :location do |merchant|
        { latitude: merchant.latitude, longitude: merchant.longitude }
      end

      field :opening_hours do |merchant|
        merchant.opening_hours.order(:day_of_week, :opens_at).map do |hours|
          { day_of_week: hours.day_of_week, opens_at: hours.opens_at.strftime("%H:%M"),
            closes_at: hours.closes_at.strftime("%H:%M") }
        end
      end
    end
  end
end
