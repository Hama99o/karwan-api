# The courier's wallet: what they have, what they owe, and how to top up.
class Api::V1::Couriers::WalletController < Api::V1::Couriers::BaseController
  def show
    authorize courier_wallet, :show?

    render_blue(Couriers::WalletSerializer, courier_wallet, view: :detailed)
  end

  # The statement. Paginated because a working courier generates entries every
  # day and the wallet screen must not fetch a year of them over a metered
  # connection.
  def entries
    authorize courier_wallet, :show?
    skip_policy_scope

    entries = courier_wallet.wallet_entries.includes(:source).newest_first

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
end
