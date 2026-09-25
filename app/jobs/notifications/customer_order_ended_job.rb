module Notifications
  # Enqueued when an order ends, and run a few seconds later: every caller
  # writes the reason (rejection, cancellation, failure) just AFTER the
  # transition, and the push must carry the same reason the screen shows.
  class CustomerOrderEndedJob < ApplicationJob
    queue_as :default
    SETTLE = 5.seconds

    def perform(order_id)
      order = Order.find_by(id: order_id)
      return if order.nil?

      CustomerOrderEnded.new(order).deliver!
    end
  end
end
