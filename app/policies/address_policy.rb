class AddressPolicy < ApplicationPolicy
  def index?   = true
  def create?  = own?
  def show?    = own?
  def update?  = own?
  def destroy? = own?

  private

  def own?
    record.user_id.present? && record.user_id == user&.id
  end

  class Scope < ApplicationPolicy::Scope
    # A customer's own pins and nobody else's. A saved address is where
    # somebody lives.
    def resolve
      return scope.none if user.nil?

      scope.where(user_id: user.id)
    end
  end
end
