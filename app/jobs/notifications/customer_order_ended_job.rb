module Notifications
  # Enqueued when an order ends, after its transaction. No wait is needed:
  # the reason is written IN the transition (`transition_to!(..., with:)`),
  # so by the time this runs the order and its reason are one fact. (It
  # used to wait 5 s and hope every caller had written the reason just
  # after; Hamma9901 found that fragility, 25 Sept 2026.)
  class CustomerOrderEndedJob < ApplicationJob
    queue_as :default

    def perform(order_id)
      order = Order.find_by(id: order_id)
      return if order.nil?

      CustomerOrderEnded.new(order).deliver!
    end
  end
end
