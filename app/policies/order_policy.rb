class OrderPolicy < ApplicationPolicy
  def index?  = true
  def create? = customer? || admin?

  # Three audiences, three different reasons to be allowed near one record —
  # and each checks a relationship, not merely a role. This is the whole of
  # "tenancy is not permission": being a courier does not let you read every
  # order, only the ones assigned to you.
  def show?
    admin? || own_order? || merchants_order? || assigned_courier?
  end

  # Only the customer whose order it is may cancel, and only while nothing has
  # been committed. The state machine is the authority on when — this predicate
  # answers WHO.
  def cancel?
    return false unless own_order? || admin?

    record.can_transition_to?(:cancelled, actor_role: admin? ? :admin : :customer)
  end

  # One predicate per board action rather than a single `update?`, so each can
  # be reasoned about and refused independently. The state machine still decides
  # WHETHER the move is legal; these decide WHO may attempt it.
  def accepted?  = merchants_order? || admin?
  def rejected?  = merchants_order? || admin?
  def preparing? = merchants_order? || admin?
  def ready?     = merchants_order? || admin?

  # Tracking a courier's position is deliberately narrow: only the people on
  # this specific job, only while it is live. Without the liveness check, a
  # customer could watch a courier for the rest of their shift from an order
  # completed last week.
  def track?
    return false if record.terminal?

    admin? || own_order? || merchants_order?
  end

  private

  def own_order?
    record.customer_id == user&.id
  end

  def merchants_order?
    merchant_owner? && record.merchant&.owner_id.present? && record.merchant.owner_id == user&.id
  end

  def assigned_courier?
    courier? && record.courier_id.present? && record.courier_id == user&.id
  end

  # A SCOPE PER ROLE, not one scope with conditionals.
  #
  # The default `Scope` is the customer's, because that is who most requests
  # come from — but a merchant asking for "orders" means a completely different
  # set, and chaining `.where(merchant_id:)` onto the customer scope returns
  # nothing at all. That was a real bug here, caught before any spec ran:
  # merchants saw an empty board.
  #
  # Each role names its own scope and the controller asks for it explicitly, so
  # a role added later cannot silently inherit the wrong set.
  class Scope < ApplicationPolicy::Scope
    # Mine, as the person who placed it.
    def resolve
      return scope.none if user.nil?

      scope.where(customer_id: user.id)
    end
  end

  # Orders for the merchant this user owns. Derived from ownership, never from
  # a merchant_id in the request — that parameter is how one restaurant reads
  # another's orders.
  class MerchantScope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user&.role?(:merchant_owner)

      scope.joins(:merchant).where(merchants: { owner_id: user.id })
    end
  end

  # Jobs assigned to this courier. Being a courier does not mean seeing every
  # order — only the ones they were given.
  class CourierScope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user&.role?(:courier)

      scope.where(courier_id: user.id)
    end
  end

  # Admin sees everything, including discarded and terminal work, because the
  # ops console exists to fix what the automation got wrong.
  class AdminScope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user&.role?(:admin)

      scope.all
    end
  end
end
