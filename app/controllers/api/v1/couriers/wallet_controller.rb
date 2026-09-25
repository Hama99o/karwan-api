# The courier's wallet: what they have, what they owe, and how to top up.
class Api::V1::Couriers::WalletController < Api::V1::Couriers::BaseController
  def show
    authorize courier_wallet, :show?

    render_blue(Couriers::WalletSerializer, courier_wallet, view: :detailed)
  end

  # The statement. Paginated because a working courier generates entries every
  # day and the wallet screen must not fetch a year of them over a metered
  # connection.
  #
  # `from` / `to` (YYYY-MM-DD, Kabul days, both inclusive, either optional):
  # the question a courier asks is "was I paid on Tuesday", and paging back
  # one screen at a time on metered data to find it is hunting, not finding.
  # A date that isn't one is the app's bug (a picker sends these), so it's a
  # 400 `bad_request`, not a sentence to translate.
  def entries
    authorize courier_wallet, :show?
    skip_policy_scope

    from, to = statement_period
    return render_bad_request if from == :invalid || to == :invalid

    entries = courier_wallet.wallet_entries.includes(:source).newest_first
    entries = entries.where(created_at: from.beginning_of_day..) if from
    entries = entries.where(created_at: ..to.end_of_day) if to

    paginate_blue(Couriers::WalletEntrySerializer, entries)
  end

  # Read-only on purpose. A courier cannot record their own settlement — the
  # whole point is that the counted figure comes from somebody else, and admin
  # records it. This endpoint exists so they can check what was recorded.
  def settlements
    authorize courier_wallet, :show?
    skip_policy_scope

    settlements = Settlement.where(courier_id: current_user.id).newest_first

    paginate_blue(Couriers::SettlementSerializer, settlements)
  end

  private

  # Each is nil (not sent), a Kabul date, or :invalid.
  def statement_period
    %i[from to].map do |key|
      raw = params[key].presence
      next nil if raw.nil?
      next :invalid unless raw.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      # Strict: `Time.zone.parse("2026-02-30")` would quietly mean 2 March.
      Date.iso8601(raw.to_s)
    rescue Date::Error
      :invalid
    end
  end
end
