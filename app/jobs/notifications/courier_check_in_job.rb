module Notifications
  # One attempt. The operator already has the overdue flag and the courier's
  # phone number; this is the courier's chance to say what happened before
  # anybody decides anything, not a second alarm.
  class CourierCheckInJob < ApplicationJob
    queue_as :default

    def perform(job_class, job_id)
      klass = [ Order, Trip ].find { |candidate| candidate.name == job_class }
      job = klass&.find_by(id: job_id)
      return if job.nil?

      CourierCheckIn.new(job).deliver!
    end
  end
end
