module Couriers
  # WHY THE OFFER HE WAS LOOKING AT IS GONE, true by construction.
  #
  # karwan-42 found an offer simply vanished at the next poll, with no
  # sentence, and the only copy the app had ("that job went to another
  # rider") described a race v0 can't have: dispatch offers one job to ONE
  # courier at a time. So the server says what actually happened, from his
  # own offer's record, for an offer that ended in the last WINDOW:
  #
  #   withdrawn  the job was cancelled, or taken back by the console
  #   taken      it is now with another courier (a console reassign, or the
  #              rare second offer); said only when literally true
  #   timed_out  he let it run out, which he can act on
  #
  # Declined and accepted are left out: he did those himself.
  class LastOffer
    WINDOW = 2.minutes
    ENDED = %w[timed_out taken withdrawn].freeze

    Result = Data.define(:job_code, :ended, :at)

    def initialize(courier, now: Time.current)
      @courier = courier
      @now = now
    end

    def call
      offer = Offer.where(courier_id: @courier.id).includes(:offerable).order(id: :desc).first
      return nil if offer.nil? || offer.status_accepted? || offer.status_declined?
      return nil if offer.status_offered? && !offer.expired? # still live: that is the offer, not its end

      at = ended_at(offer)
      return nil if at.nil? || at < @now - WINDOW

      Result.new(job_code: offer.offerable&.code, ended: ending(offer, at), at: at)
    end

    private

    def ended_at(offer)
      return offer.responded_at || offer.expires_at if offer.status_timed_out? || offer.status_offered?

      offer.responded_at || offer.updated_at # superseded
    end

    def ending(offer, at)
      job = offer.offerable
      return "withdrawn" if job_ended_by(job, at)
      return "taken" if offer.status_superseded? && job&.courier_id.present? && job.courier_id != @courier.id
      return "withdrawn" if offer.status_superseded?

      "timed_out"
    end

    # Cancelled or failed at or before his offer ended: it was withdrawn from
    # under him, not something he let run out.
    def job_ended_by(job, at)
      return false if job.nil?

      %w[cancelled failed].any? do |status|
        job.status == status && (ended = job.public_send(:"#{status}_at")) && ended <= at + 1.second
      end
    end
  end
end
