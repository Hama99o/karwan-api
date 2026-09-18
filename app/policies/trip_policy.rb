# A ride, authorised the same way a delivery is.
#
# Separate from OrderPolicy rather than shared, even though the predicates
# currently read almost identically. The two demand types diverge — a ride has
# a passenger and no merchant, and its cancellation rules already differ — and
# a shared policy would become the conditional this architecture exists to
# avoid. Duplication between demand types is cheaper than coupling between them.
class TripPolicy < ApplicationPolicy
  def create? = customer? || admin?

  def show?
    admin? || own_trip? || assigned_courier?
  end

  def cancel?
    return false unless own_trip? || admin?

    record.can_transition_to?(:cancelled, actor_role: admin? ? :admin : :customer)
  end

  # Narrower than a delivery's, because there is no merchant who also needs to
  # see it — only the passenger and the driver on this ride, and only while it
  # is live.
  def track?
    return false if record.terminal?

    admin? || own_trip?
  end

  private

  def own_trip?
    record.passenger_id == user&.id
  end

  def assigned_courier?
    courier? && record.courier_id.present? && record.courier_id == user&.id
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if user.nil?

      scope.where(passenger_id: user.id)
    end
  end

  class CourierScope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user&.role?(:courier)

      scope.where(courier_id: user.id)
    end
  end

  class AdminScope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user&.role?(:admin)

      scope.all
    end
  end
end
