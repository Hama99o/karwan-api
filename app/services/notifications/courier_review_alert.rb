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
          # NO NOTE. A PUSH CARRIES IDENTIFIERS, NOT CONTENT (24 Sept 2026).
          # The review note or rejection reason is an operator's free-text
          # assessment of a PERSON — "the guarantor denied it" — the only
          # thing a human typed about another human in any payload. It crossed
          # Google's servers in the clear, sat in the OS's notification store,
          # and could land on a phone a rejected applicant shares with his
          # family. Nothing is lost: this push is data-only, so the OS never
          # showed it, and the application screen it opens fetches both the
          # note and the reason fresh (couriers/registration_serializer).
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
