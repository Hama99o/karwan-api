module Notifications
  # One attempt, and deliberately not repeated.
  #
  # Unlike the merchant's order alert, there is a human at the door about to
  # knock: if the notification does not arrive, the courier rings the number he
  # already has. Repeating a push at somebody who is thirty seconds from
  # meeting the sender is noise.
  class ArrivalAlertJob < ApplicationJob
    queue_as :default

    def perform(job_class, job_id)
      klass = [ Order, Trip ].find { |candidate| candidate.name == job_class }
      return if klass.nil?

      job = klass.find_by(id: job_id)
      return if job.nil?

      ArrivalAlert.new(job).deliver!
    end
  end
end
