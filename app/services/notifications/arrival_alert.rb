module Notifications
  # "YOUR COURIER IS AT THE GATE."
  #
  # The second use of one piece of push plumbing — the merchant's order alert
  # and the applicant's review outcome are the others.
  #
  # ── WHY THIS IS A NOTIFICATION AND NOT A MESSAGE ──────────────────────────
  # Hamma9900 asked for customer and courier to reach each other **especially
  # at the arrival moment**, and offered a chat as the way. A chat reaches
  # somebody who has the app open; the person waiting for a delivery does not
  # have it open — they are in the kitchen, or on another floor, or on a phone
  # somebody else is using (`AFGHAN_UX.md` §7). **Push is what reaches them,
  # and the phone number is what fixes it when push does not.**
  #
  # So this is one of three channels for the same moment, the same discipline
  # as the merchant alert: the notification, the status screen the app already
  # polls, and the tappable phone number that needs no data at all.
  class ArrivalAlert
    def initialize(job, client: nil)
      @job = job
      @client = client || FcmClient.new
    end

    def deliver!
      tokens = recipient&.device_tokens&.active&.pluck(:token) || []

      result = @client.send_to(
        tokens,
        title_key: "customer.arrival.title",
        body_key: "customer.arrival.body",
        data: {
          # `kind` rather than a class name: the app routes on the demand type,
          # and a Ruby class name in a payload is an implementation detail the
          # client would then depend on.
          kind: @job.class::JOB_KIND,
          job_id: @job.id,
          code: @job.code,
          # SO THEY CAN RING HIM WITHOUT OPENING ANYTHING. The number is the
          # fallback for this exact notification failing, and it costs no data.
          courier_phone: @job.courier&.phone,
          deep_link: "karwan://orders"
        }
      )

      record(result, tokens.size)
      result
    end

    private

    # The person AT THE DOOR, not the person who paid — those are different
    # people whenever somebody orders for a relative, which is a primary use
    # here. The snapshot columns are the authority, exactly as they are for the
    # courier's own step list.
    def recipient
      @job.is_a?(Trip) ? @job.passenger : @job.customer
    end

    def record(result, token_count)
      AuditLog.record!(
        action: "arrival.announced",
        target: @job,
        details: {
          channel: "push", status: result.status.to_s, devices: token_count,
          delivered: result.delivered, failed: result.failed,
          # Not a bug, and not an escalation either: the customer is about to
          # be met in person by the courier who is already outside. Recorded so
          # "was she told" has an answer if a delivery goes wrong at the door.
          reached: result.any_delivered?
        }
      )
    end
  end
end
