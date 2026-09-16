class MerchantPolicy < ApplicationPolicy
  # Browsing is open, including to guests. Correction 10: let them see a
  # merchant before asking for anything.
  def index? = true
  def show?  = true

  # Merchants are not self-serve in v0 — admin onboards them.
  def create?  = admin?
  def destroy? = admin?

  # APPLYING IS NOT CREATING. `create?` is the console's power to bring a shop
  # into existence with terms; this is a signed-in person leaving their details
  # so Hamma9900 can call them. The row it writes is a `lead`, which no scope
  # in the app treats as a merchant.
  def apply? = user.present?

  # Their own application, found by the phone they signed in with — the phone
  # IS the identity, and an applicant is not the owner yet, because assigning
  # an owner grants the merchant role and that must wait for a human.
  def show_application?
    return false if user.nil?

    record.owner_id == user.id || (record.owner_phone.present? && record.owner_phone == user.phone)
  end

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
