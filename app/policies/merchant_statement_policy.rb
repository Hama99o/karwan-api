# A shop's own earnings records.
class MerchantStatementPolicy < ApplicationPolicy
  def show? = merchants_statement? || admin?

  # ── DERIVED FROM OWNERSHIP, NEVER FROM A PARAMETER ────────────────────────
  #
  # The same reasoning `OrderPolicy::MerchantScope` gives: a `merchant_id` in
  # the request is how one restaurant reads another's figures. The scope starts
  # from the signed-in person's merchants and cannot be widened by anything the
  # caller sends.
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if user.nil?

      scope.where(merchant_id: Merchant.where(owner_id: user.id).select(:id))
    end
  end

  private

  def merchants_statement?
    record.merchant&.owner_id == user&.id
  end
end
