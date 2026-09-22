module Orders
  # ── WHY THE ORDER ENDED, FOR THE PERSON WHO LOST THE DINNER ────────────────
  #
  # The merchant board has always REFUSED a rejection without a reason from a
  # fixed list, and the controller says why: *"free text would mean nobody can
  # count why orders are refused."* The reason was then shown to the operator
  # and to nobody else. The customer got `status: "rejected"` and a timeline,
  # and had to guess.
  #
  # The guess matters, because the four reasons imply four different next
  # actions and the customer is standing in their kitchen deciding:
  #
  #   out_of_stock  order something else from the same shop, now
  #   too_busy      the same shop, later
  #   closing       a different shop, tonight
  #   no_answer     a different shop, and this one may have a broken tablet
  #
  # `AFGHAN_UX.md` is the reason this is a CODE and not a sentence. The server
  # cannot say "they have run out" in Pashto, and a server-written English
  # string is untranslatable on the device — the same rule `Couriers::JobSteps`
  # states for its step labels. The client holds the words.
  class EndedReason
    # The column that carries the reason, per unhappy ending. `delivered` is
    # absent deliberately: an order that arrived has no reason to explain, and
    # returning one would put an explanation on the happy path.
    REASON_COLUMN = {
      "rejected"  => :rejection_reason,
      "cancelled" => :cancellation_reason,
      "failed"    => :failure_reason
    }.freeze

    # A rejection whose reason column is empty. Real: `rejection_reason` is
    # nullable, admin cancels through the console, and rows predate the column.
    # Named rather than nil so the client renders "we do not know" instead of
    # rendering nothing, which reads as a bug to the person it happened to.
    UNKNOWN = "unknown".freeze

    # Nobody recorded the transition, so nothing can say who ended it. Distinct
    # from `system` — one means a machine did it, the other means nothing knows.
    SYSTEM = "system".freeze

    def self.for(order) = new(order).call

    def initialize(order)
      @order = order
    end

    def call
      column = REASON_COLUMN[@order.status.to_s]
      return nil if column.nil?

      { outcome: @order.status.to_s, code: @order.public_send(column).presence || UNKNOWN,
        ended_by: ended_by }
    end

    private

    # WHO, from the transition log rather than from `cancelled_by_role` — which
    # exists only for cancellations, is written by two paths and by neither the
    # timeout job nor anything else, and is read by nothing at all. The log is
    # the one-way door; a column beside it is a second answer that can disagree.
    #
    # `StatusTransition#system?` is BOTH actor columns empty. That matters here
    # more than anywhere: an operator cancelling from the console has no
    # `actor_id` — they are an `AdminUser` — and used to come out as `system`,
    # so a person's decision was reported to the customer as a machine's. The
    # two send them to different places. "Nobody at the shop answered" means try
    # another shop; **`admin` means somebody at Karwan decided it, and there is
    # a number in the app to ring.**
    #
    # Nil when there is no transition row at all. That is a real state — the
    # stress seed produces it in bulk — and answering "system" there would be
    # asserting a cause the data does not carry, which is the same mistake the
    # admin report made until it was rendered against a real database.
    def ended_by
      transition = @order.transitions.detect { |t| t.to_status == @order.status.to_s }
      return nil if transition.nil?

      transition.system? ? SYSTEM : transition.actor_role.to_s.presence
    end
  end
end
