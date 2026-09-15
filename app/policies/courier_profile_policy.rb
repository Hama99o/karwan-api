class CourierProfilePolicy < ApplicationPolicy
  # A courier reads and writes their OWN profile. Holding the courier role does
  # not grant access to anyone else's.
  def show?   = own? || admin?
  def update? = own? || admin?

  # Anyone signed in may APPLY, and that is deliberate: the courier role is
  # what applying is FOR, so requiring it would be a door locked from the
  # inside. The application is worth nothing until a human approves it.
  def create? = user.present?

  # Approval is an admin act with a name attached — never self-serve. A courier
  # approving themselves is the whole reason the guarantor and the tazkira are
  # collected.
  def approve? = admin?
  def reject?  = admin?

  private

  def own?
    record.user_id.present? && record.user_id == user&.id
  end
end
