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
      Attachments::PublicUrl.for(merchant.logo)
    end

    field :storefront_photo_url do |merchant|
      if merchant.storefront_photo.attached?
        Attachments::PublicUrl.for(merchant.storefront_photo)
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

      # ── THE DISTANCE THE CUSTOMER READS ────────────────────────────────────
      #
      # From `options[:distances]`, a single OSRM `/table` request for the whole
      # page, and NOT measured here. It used to call `Geo::Distance.km`
      # directly while the fare went through `DistanceResolver`, so **the card
      # said 3.6 km and the fare was computed from 4.6 km** — a number the
      # customer was shown that was not true.
      #
      # Falls back to straight line for the WHOLE list when the router is
      # unreachable, never per row: a mixture would have the customer sorting
      # road distances against crow-flight ones without being told.
      #
      # Computed server-side either way. A client that measures its own
      # distance will disagree with the fee the server charged.
      field :distance_km do |merchant, options|
        Customers::MerchantSerializer.distance_for(merchant, options)
      end

      # WHICH METHOD PRODUCED IT, on every distance we show — not only on a
      # quote. A number a customer saw has to be explainable later, and after
      # the switch to roads "why was that one cheaper" is the first question.
      field :distance_source do |_merchant, options|
        options[:distances]&.source
      end

      field :eta_minutes do |merchant, options|
        km = Customers::MerchantSerializer.distance_for(merchant, options)
        travel = Geo::Distance.travel_minutes(km)
        next nil if travel.nil?

        # The kitchen, plus the ride. A customer waiting for food does not care
        # which half of the wait is cooking.
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

    # ONE PLACE, because two fields need the same number and a second
    # measurement is how two figures on one card disagree.
    #
    # A caller that passes no table — the detail screen, which is one merchant
    # rather than a list — measures the straight line. That is a single
    # `/route` call away from being routed too, and is recorded in
    # docs/NOTES.md rather than half-done here.
    def self.distance_for(merchant, options)
      return nil if options[:from].blank?

      table = options[:distances]
      return table.km(merchant.id) if table

      Geo::Distance.km(from_lat: options[:from][0], from_lng: options[:from][1],
                       to_lat: merchant.latitude, to_lng: merchant.longitude)
    end
  end
end
