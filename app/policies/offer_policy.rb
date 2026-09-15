class OfferPolicy < ApplicationPolicy
  # An offer is addressed to one courier. Nobody else may read or answer it —
  # not another courier, and not the customer whose job it is.
  def show?    = courier? || admin?
  def accept?  = own? && answerable?
  def decline? = own? && answerable?

  private

  def own?
    record.courier_id.present? && record.courier_id == user&.id
  end

  # Already answered is not answerable. Without this, a double-tap on a slow
  # connection accepts the same job twice, or accepts one that was superseded.
  def answerable?
    record.status_offered?
  end
end
