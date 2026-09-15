class CourierWalletPolicy < ApplicationPolicy
  # A courier sees their own wallet and nobody else's. Holding the courier role
  # grants nothing here — only owning this wallet does.
  def show? = own? || admin?

  # Money only moves through admin: a top-up is a bank deposit somebody
  # reconciled, a reimbursement is a policy decision, an adjustment needs a
  # named author. A courier crediting their own wallet is the one thing this
  # design exists to prevent.
  def top_up?  = admin?
  def adjust?  = admin?
  def settle?  = admin?

  private

  def own?
    record.user_id.present? && record.user_id == user&.id
  end
end
