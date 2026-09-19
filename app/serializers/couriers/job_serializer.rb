module Couriers
  # A job as the COURIER sees it: a step list and the money, for either demand
  # type.
  #
  # `kind` tells the app which words to use ("rider" in the delivery tab,
  # "driver" in the ride tab) — it does NOT tell it to render a different
  # screen. That is the whole point of the step list.
  class JobSerializer < ApplicationSerializer
    identifier :id

    fields :code, :status, :currency

    # WHAT HE IS AGREEING TO, before he accepts. Hamma9900: *"same for rider,
    # they should check before accepting, they should see if other customers
    # are allowed or not."*
    #
    # A job he cannot combine is worth less to him at the same fee, so premium
    # has to be visible on the offer rather than discovered afterwards. Sent as
    # the tier plus the plain fact it implies, because the second is what the
    # screen actually says and the server must not make the app derive a
    # promise from an enum.
    field :service_tier do |job|
      job.service_tier
    end

    field :can_be_combined do |job|
      ServiceTiers.batchable?(job.service_tier)
    end

    field :kind do |job|
      job.class.job_kind
    end

    # What the courier earns. Shown before they accept, per correction 4 —
    # nobody should have to take a job to find out what it pays.
    field :earnings do |job|
      job.is_a?(Order) ? job.courier_fee : job.courier_earnings
    end

    # What they must put up front. Zero on a ride, and saying so explicitly is
    # cheaper than every caller remembering which demand type advances money.
    field :advance_required do |job|
      job.courier_advance
    end

    field :total_to_collect do |job|
      job.is_a?(Order) ? job.customer_total : job.fare
    end

    view :offer do
      field :expires_at do |_job, options|
        options[:offer]&.expires_at
      end

      # A countdown, not a deadline: the phone's clock may be wrong, and a
      # wrong clock would either expire the offer instantly or never.
      field :seconds_remaining do |_job, options|
        next nil if options[:offer].nil?

        [ (options[:offer].expires_at - Time.current).ceil, 0 ].max
      end

      field :pickup do |job|
        coords = job.pickup_coordinates
        next nil if coords.nil?

        { latitude: coords[0], longitude: coords[1] }
      end

      field :distance_km do |job, options|
        next nil if options[:from].blank? || job.pickup_coordinates.nil?

        Geo::Distance.km(from_lat: options[:from][0], from_lng: options[:from][1],
                         to_lat: job.pickup_coordinates[0], to_lng: job.pickup_coordinates[1])
      end

      field :place_name do |job|
        job.is_a?(Order) ? job.merchant.name : nil
      end

      # ── AND HOW FAR HE THEN CARRIES IT ──────────────────────────────────────
      #
      # PRODUCT.md names both on the offer card — "restaurant name and distance,
      # CUSTOMER DISTANCE" — and only the first was served. `distance_km` above
      # is the ride TO the pickup; this is the leg after it, which is most of the
      # courier's time and none of it was on the card.
      #
      # It changes the answer. One kilometre to the shop and twelve to the door
      # is a different job from one and one, at the same fee, and he was deciding
      # accept-or-decline without the number that separates them.
      #
      # `distance_km` is NOT renamed to match, though the pair reads asymmetric.
      # The app already parses it, and a rename is a client break for a cosmetic
      # gain — so the name carries the disambiguation instead.
      #
      # One field for both demand types: on a delivery it is merchant to
      # customer, on a ride it is passenger to destination. Both are "how far he
      # carries it after pickup", and both are the FROZEN column the fare was
      # quoted from — never re-measured, for the reason `Orders::ArrivalWindow`
      # gives at length.
      field :onward_distance_km do |job|
        job.distance_km
      end
    end

    view :active do
      # HAS HE ALREADY TOLD THEM? Without this the courier's own screen cannot
      # know, so the "I am at the gate" button would stay on screen doing
      # nothing on a second tap — the server is idempotent, but a button that
      # visibly does nothing is worse than no button.
      #
      # A ride uses its own state for this, so both demand types answer the
      # same question through one field and the app never learns the difference.
      field :arrived_at do |job|
        job.is_a?(Trip) ? job.arrived_at : job.courier_arrived_at
      end

      # ── WHAT THE CUSTOMER WAS PROMISED, SHOWN TO THE PERSON IT IS ABOUT ────
      #
      # `arrival_window` was on `customers/order_serializer` and
      # `customers/track_serializer` and on nothing the courier can see. So the
      # customer read "۱۳:۳۰ – ۱۳:۴۰" and the one man whose movements make that
      # sentence true or false had no idea it had been said.
      #
      # NOT SYMMETRY, AND NOT AN ESTIMATE FOR HIM. He can judge his own arrival
      # better than this arithmetic can. What he cannot know is **the claim made
      # on his behalf**, and that claim is the expectation he is measured
      # against — by the customer on the phone, and by anyone reading a late
      # delivery afterwards. A courier told "you were forty minutes" who was
      # never told forty was promised cannot answer.
      #
      # THE SAME CALL the customer's payload makes, deliberately. Two
      # computations of one promise is how the two screens come to disagree, and
      # a courier and customer holding different windows is worse than neither
      # holding one.
      #
      # NIL FOR A RIDE, and that is the honest answer rather than a gap: no
      # customer-facing ride payload carries an arrival window, so there is no
      # promise to relay. `Orders::ArrivalWindow` reads `merchant`, `ready_at`
      # and `picked_up_at`, none of which a `Trip` has — it would raise, not
      # degrade. Same guard shape as `items` below.
      field :arrival_window do |job|
        next nil unless job.is_a?(Order)

        window = Orders::ArrivalWindow.for(job)
        next nil if window.nil?

        { from: window.from, to: window.to, basis: window.basis }
      end

      # THE step list. One screen, one action at a time, both demand types.
      field :steps do |job|
        Couriers::JobSteps.new(job).call
      end

      field :items do |job|
        next [] unless job.is_a?(Order)

        job.order_items.map do |item|
          { name: item.name, quantity: item.quantity,
            options: item.selected_options.map { |o| "#{o.option_name}: #{o.value_name}" } }
        end
      end

      # Problem buttons, per PRODUCT.md: at every step, recording a reason and
      # reaching admin. Sent as keys so the app renders them in the right
      # language.
      field :problem_reasons do |job|
        (job.is_a?(Order) ? Order.failure_reasons : Trip.failure_reasons).keys
      end
    end
  end
end
