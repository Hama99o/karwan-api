module Notifications
  # TELLING AN APPLICANT WHAT WE DECIDED.
  #
  # The third use of one piece of plumbing — the merchant's order alert and the
  # customer's arrival notice are the others — and the one where a missing
  # notification means somebody **waits forever for an approval nobody told
  # them about.** A courier who has sent his tazkira and heard nothing assumes
  # he was refused, and a courier we convinced and then lost is the most
  # expensive kind of loss on the supply side, which is the scarce side.
  #
  # ── THREE OUTCOMES, THREE MESSAGES, AND THEY MUST NOT BE ONE ─────────────
  #
  #   approved   — "you can start". The only one that is good news.
  #   needs_more — "we need one more thing". NOT a refusal, and the difference
  #                is the whole reason `needs_more` is its own state.
  #   rejected   — "we cannot accept you", with a human's reason.
  #
  # Sent as KEYS, never prose: the server cannot write Pashto, so the app
  # renders its own copy. Same rule as the job step list's `label_key` and the
  # `missing` field names.
  class CourierReviewAlert
    OUTCOMES = {
      "approved" => { title: "courier.review.approved.title", body: "courier.review.approved.body" },
      "needs_more" => { title: "courier.review.needs_more.title", body: "courier.review.needs_more.body" },
      "rejected" => { title: "courier.review.rejected.title", body: "courier.review.rejected.body" }
    }.freeze

    def initialize(profile, client: nil)
      @profile = profile
      @client = client || FcmClient.new
    end

    def deliver!
      copy = OUTCOMES[@profile.verification_status]
      # Nothing to announce for `pending` or `suspended`: one is the state an
      # application starts in and the other is an enforcement action a human
      # takes for a reason they will convey themselves.
      return nil if copy.nil?

      tokens = @profile.user&.device_tokens&.active&.pluck(:token) || []

      result = @client.send_to(
        tokens,
        title_key: copy[:title], body_key: copy[:body],
        data: {
          status: @profile.verification_status,
          # WHAT IS STILL WANTED, so the notification can say it rather than
          # only inviting them to open the app and guess. Field names, because
          # the app writes the words.
          #
          # JSON-ENCODED DELIBERATELY. `FcmClient` runs every data value
          # through `to_s` — FCM's data map is string-to-string — so an array
          # of symbols would arrive as the literal `"[:id_document, :selfie]"`,
          # Ruby inspect output that the app would have to parse as Ruby. Any
          # structured value on this path has to be encoded on purpose or it
          # ships as debug output.
          missing: @profile.missing_for_approval.map(&:to_s).to_json,
          # The one prose field, written by a human and shown as given: a
          # courier who cannot see WHY cannot fix it.
          note: @profile.review_note.presence || @profile.rejection_reason.presence,
          deep_link: "karwan://apply-rider"
        }
      )

      record(result, tokens.size)
      result
    end

    private

    # Written down because "did he ever get told" is the first question when an
    # applicant complains, and because an applicant with no registered device
    # is a HUMAN follow-up rather than a bug — he needs a phone call, and that
    # has to be visible in the console rather than buried in a log.
    def record(result, token_count)
      AuditLog.record!(
        action: "courier.review_notified",
        target: @profile,
        details: {
          channel: "push", outcome: @profile.verification_status,
          status: result.status.to_s, devices: token_count,
          delivered: result.delivered, failed: result.failed,
          needs_human_contact: !result.any_delivered?
        }
      )
    end
  end
end
