module Couriers
  # ONE ACTIVE-JOB SCREEN FOR BOTH DEMAND TYPES.
  #
  # Correction 7: the courier app renders an ordered step list supplied by the
  # serializer — each step a location, an action, and optionally an amount. A
  # delivery serialises four steps, a ride three. `Order` and `Trip` stay
  # separate tables; only the courier's view unifies.
  #
  # This is not speculative generality. It is how a third demand type later
  # costs a step list rather than a new screen, and it is what keeps `if food`
  # out of the mobile code — which matters because the courier screen is used
  # one-handed, in motion, in sunlight, with one action visible at a time.
  # Grab, Gojek and Yandex Go all do exactly this.
  #
  # LABELS ARE i18n KEYS, NEVER ENGLISH. The server does not know how to say
  # "collect the cash" in Pashto, and a server-written English string is
  # untranslatable on the device. The client holds the words; we hold the order
  # of operations and the numbers.
  class JobSteps
    def initialize(job)
      @job = job
    end

    def call
      steps = @job.is_a?(Order) ? delivery_steps : ride_steps
      mark_progress(steps)
    end

    private

    # Four legs: to the merchant, hand over money, to the customer, take money.
    # The courier is out of pocket between steps 2 and 4, which is why the
    # amounts are shown before each one rather than after.
    def delivery_steps
      [
        {
          key: "go_to_merchant",
          label_key: "courier.steps.go_to_merchant",
          status_after: nil,
          location: coordinates(@job.merchant&.latitude, @job.merchant&.longitude),
          landmark_note: @job.merchant&.landmark_note,
          place_name: @job.merchant&.name,
          phone: @job.merchant&.phone,
          amount: nil
        },
        {
          key: "pay_merchant",
          label_key: "courier.steps.pay_merchant",
          # The action that moves the job. One button, one transition, one
          # timestamp column — never a status overwritten in place.
          status_after: "picked_up",
          location: coordinates(@job.merchant&.latitude, @job.merchant&.longitude),
          place_name: @job.merchant&.name,
          phone: @job.merchant&.phone,
          # What they hand over: the items less our commission. Their own money
          # until the customer pays them back.
          amount: @job.merchant_payout,
          amount_direction: "pay"
        },
        {
          key: "go_to_customer",
          label_key: "courier.steps.go_to_customer",
          status_after: nil,
          location: coordinates(@job.delivery_latitude, @job.delivery_longitude),
          # The landmark note is the address in this market. A pin alone is not
          # enough in a city navigated by landmark.
          landmark_note: @job.delivery_landmark_note,
          has_voice_note: false,
          phone: @job.customer_phone,
          amount: nil
        },
        {
          key: "collect_and_deliver",
          label_key: "courier.steps.collect_and_deliver",
          status_after: "delivered",
          location: coordinates(@job.delivery_latitude, @job.delivery_longitude),
          landmark_note: @job.delivery_landmark_note,
          phone: @job.customer_phone,
          amount: @job.customer_total,
          amount_direction: "collect"
        }
      ]
    end

    # Three legs: to the passenger, start, finish and take the fare. Nothing is
    # advanced, which is why there is no pay step — and why a courier too short
    # for a delivery can still take a ride.
    def ride_steps
      [
        {
          key: "go_to_pickup",
          label_key: "courier.steps.go_to_pickup",
          status_after: "arrived",
          location: coordinates(@job.pickup_latitude, @job.pickup_longitude),
          landmark_note: @job.pickup_landmark_note,
          phone: @job.passenger_phone,
          amount: nil
        },
        {
          key: "start_ride",
          label_key: "courier.steps.start_ride",
          status_after: "in_progress",
          location: coordinates(@job.pickup_latitude, @job.pickup_longitude),
          phone: @job.passenger_phone,
          amount: nil
        },
        {
          key: "complete_and_collect",
          label_key: "courier.steps.complete_and_collect",
          status_after: "completed",
          location: coordinates(@job.dropoff_latitude, @job.dropoff_longitude),
          landmark_note: @job.dropoff_landmark_note,
          phone: @job.passenger_phone,
          amount: @job.fare,
          amount_direction: "collect"
        }
      ]
    end

    # Exactly one step is `current`, and it is the first one not yet done. The
    # courier screen shows one action at a time — deciding which here rather
    # than on the device means the phone cannot disagree with the server about
    # what happens next.
    #
    # NAVIGATION STEPS HAVE NO ACTION, which the first version got wrong:
    # "go to the merchant" carries no transition, so it could never be
    # completed, stayed `current` forever, and blocked the whole list. A
    # navigation step is done once the action it leads to is done — you have
    # arrived when you have paid.
    def mark_progress(steps)
      reached = statuses_reached

      with_completion = steps.each_with_index.map do |step, index|
        done = if step[:status_after].present?
                 reached.include?(step[:status_after])
        else
                 # The next step that actually does something. If that is done,
                 # getting there must have happened.
                 following = steps[(index + 1)..].find { |later| later[:status_after].present? }
                 following.present? && reached.include?(following[:status_after])
        end

        step.merge(completed: done)
      end

      current_assigned = false
      with_completion.map do |step|
        is_current = !step[:completed] && !current_assigned
        current_assigned ||= is_current

        step.merge(current: is_current)
      end
    end

    def statuses_reached
      @statuses_reached ||= @job.transitions.pluck(:to_status).to_set
    end

    def coordinates(latitude, longitude)
      return nil if latitude.nil? || longitude.nil?

      { latitude: latitude, longitude: longitude }
    end
  end
end
