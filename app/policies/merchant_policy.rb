class MerchantPolicy < ApplicationPolicy
  # Browsing is open, including to guests. Correction 10: let them see a
  # merchant before asking for anything.
  def index? = true
  def show?  = true

  # Merchants are not self-serve in v0 — admin onboards them.
  def create?  = admin?
  def destroy? = admin?

  # The owner may edit their own shop; admin may edit anyone's. Owning it is
  # what grants this, not merely holding the merchant_owner role — that
  # distinction is the whole of edu-safi's tenancy-is-not-permission lesson.
  def update?
    admin? || owner?
  end

  # Opening and closing is the single most important control in the system, so
  # it is its own predicate rather than folded into `update?`: admin must be
  # able to close a shop on its behalf without being able to rewrite its menu.
  def toggle_open?
    admin? || owner?
  end

  def manage_catalog?
    admin? || owner?
  end

  def owner?
    merchant_owner? && record.owner_id.present? && record.owner_id == user&.id
  end

  class Scope < ApplicationPolicy::Scope
    # What a CUSTOMER may see: live, approved merchants only. A pending or
    # suspended merchant is invisible, and a discarded one does not exist.
    def resolve
      scope.kept.status_active
    end
  end
end
