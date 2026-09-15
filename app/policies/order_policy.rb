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

  class Scope < ApplicationPolicy::Scope
    # A customer sees their own orders and nobody else's. Each role namespace
    # narrows this further with its own scope where the question differs.
    def resolve
      return scope.none if user.nil?

      scope.where(customer_id: user.id)
    end
  end
end
