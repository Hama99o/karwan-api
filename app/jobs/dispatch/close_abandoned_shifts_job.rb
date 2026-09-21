module Dispatch
  # Closes shifts nobody ended.
  #
  # A courier whose app was killed never sends "off", so their shift stays open
  # and counts as available capacity forever — which inflates the denominator in
  # `/admin/reports` and makes utilisation look WORSE than it is, the opposite
  # bias to the one `courier_shifts` was built to remove.
  #
  # Cheap and idempotent, like the two jobs beside it: a partial-indexed read
  # over open shifts only, and a second run finds nothing left to close.
  class CloseAbandonedShiftsJob < ApplicationJob
    queue_as :default

    def perform
      closed = CourierShift.close_abandoned!
      Rails.logger.info("[shifts] closed #{closed} abandoned shift(s)") if closed.positive?
      closed
    end
  end
end
