module Notifications
  # "ARE YOU ALL RIGHT? IF ANYTHING HAS HAPPENED, TELL US."
  #
  # `MONEY_AND_SETTLEMENT.md` §9, Hamma9900's instruction: *"Before a timeout
  # takes a job away, the platform contacts the courier. Tell him: if there is
  # any emergency tell us, if there is anything tell us, if the charge is
  # finished."* The honest explanations are ordinary — a flat battery, an
  # accident, a locked gate — and *"a platform that reassigns silently and
  # penalises treats a flat battery like theft."* So: ask, wait, then reassign.
  #
  # Sent ONCE per stuck state, by `Dispatch::JobTimeoutsJob` at the moment it
  # first flags the job — the flag is already deduplicated per state, so the
  # courier is asked once rather than every minute.
  #
  # Only for states the COURIER owns (see `COURIER_STATES`): a job stuck in the
  # kitchen is the shop's delay, and asking the courier about it would be
  # asking the wrong person.
  #
  # KEYS, never prose — the app renders its own Pashto and Dari, as for every
  # other push. The support number rides in the data so he can ring without
  # opening anything, which is the channel that works when data does not.
  #
  # Behind `courier_check_in_enabled` (off): the app must know this
  # notification before it is sent one. See `docs/NOTES.md` for its half.
  class CourierCheckIn
    TITLE_KEY = "courier.check_in.title".freeze
    BODY_KEY = "courier.check_in.body".freeze

    COURIER_STATES = {
      "Order" => %w[ready picked_up],
      "Trip" => %w[accepted arrived in_progress]
    }.freeze

    def self.applies_to?(job)
      job.courier_id.present? && COURIER_STATES.fetch(job.class.name, []).include?(job.status)
    end

    def initialize(job, client: nil)
      @job = job
      @client = client || FcmClient.new
    end

    def deliver!
      return nil unless self.class.applies_to?(@job)

      tokens = @job.courier.device_tokens.active.pluck(:token)
      result = @client.send_to(
        tokens,
        title_key: TITLE_KEY,
        body_key: BODY_KEY,
        data: {
          kind: @job.class::JOB_KIND,
          job_id: @job.id,
          code: @job.code,
          status: @job.status,
          support_phone: Setting.fetch("support_phone"),
          deep_link: "karwan://open/check-in/#{@job.class::JOB_KIND}/#{@job.id}"
        }
      )

      AuditLog.record!(
        action: "courier.checked_in", target: @job,
        details: { channel: "push", status: result.status.to_s, devices: tokens.size,
                   delivered: result.delivered, failed: result.failed,
                   job_status: @job.status, reached: result.any_delivered? }
      )
      result
    end
  end
end
