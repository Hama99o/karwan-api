module Notifications
  # One attempt, unlike the merchant's order alert.
  #
  # The difference is what a miss costs and how long it stays true: a merchant
  # alert is about an order that expires in two minutes, so it repeats. A review
  # outcome is still true tomorrow, and the applicant's own screen shows it the
  # moment he opens the app — `GET /courier/registration` is the source of
  # truth, and this notification is only what brings him back to it.
  #
  # So a failure here is logged and escalated to a human via the audit row
  # rather than retried into a ring.
  class CourierReviewAlertJob < ApplicationJob
    queue_as :default

    def perform(courier_profile_id)
      profile = CourierProfile.find_by(id: courier_profile_id)
      return if profile.nil?

      CourierReviewAlert.new(profile).deliver!
    end
  end
end
