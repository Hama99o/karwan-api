module Dispatch
  # Expires offers nobody answered, and moves each job to the next courier.
  #
  # THIS IS WHAT MAKES DISPATCH EXIST. Without it an unanswered offer stays
  # `offered` forever, the job is never re-offered, and the customer watches a
  # screen that will never change. `Offer#expired?` and the `expired` scope were
  # written before this job existed, which made the whole mechanism look
  # implemented while nothing ran it.
  #
  # Idempotent and safe to run often: it only touches offers whose deadline has
  # genuinely passed and which are still unanswered.
  class ExpireOffersJob < ApplicationJob
    queue_as :default

    def perform
      expired = Offer.expired.includes(:offerable).to_a
      return { expired: 0, reoffered: 0 } if expired.empty?

      reoffered = 0

      expired.each do |offer|
        # Each offer in its own transaction: one job with no courier left must
        # not roll back the expiry of every other offer in the batch.
        ApplicationRecord.transaction do
          offer.respond!(:timed_out)
          reoffered += 1 if OfferService.new(offer.offerable).call.present?
        end
      rescue StandardError => e
        # A single bad job must not stop the queue. Reported rather than
        # swallowed, because a silently skipped expiry is an order that sits.
        Rails.logger.error("[dispatch] failed to expire offer #{offer.id}: #{e.class}: #{e.message}")
      end

      { expired: expired.size, reoffered: reoffered }
    end
  end
end
