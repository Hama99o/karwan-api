# Deny by default. Every predicate is false until a subclass says otherwise, so
# a policy that forgets an action refuses it rather than allowing it.
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index?   = false
  def show?    = false
  def create?  = false
  def update?  = false
  def destroy? = false

  # Belonging to something is not permission to act on it. edu-safi's lesson:
  # `current_organization` is tenancy, not authorisation. Helpers here read
  # from the authenticated user's own roles and nothing else.
  def admin?
    user&.role?(:admin) || false
  end

  def courier?
    user&.role?(:courier) || false
  end

  def merchant_owner?
    user&.role?(:merchant_owner) || false
  end

  def customer?
    user&.role?(:customer) || false
  end

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      raise NotImplementedError, "#{self.class} must implement #resolve"
    end

    private

    attr_reader :user, :scope
  end
end
