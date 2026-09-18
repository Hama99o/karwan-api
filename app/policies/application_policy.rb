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

  # ── THIS IS WHERE ROLE ACCESS IS ENFORCED ─────────────────────────────────
  #
  # Not in a controller filter, and not from anything the client sends. These
  # four helpers and the scopes below them read the authenticated user's own
  # `user_roles` rows and nothing else — so a role in a param, a header or a
  # session cannot buy access, and four roles in one app is exactly the shape
  # where that gets forgotten.
  #
  # `Authenticatable` used to carry a `current_role` and a `require_role!` that
  # read like this check and had no callers at all. They are gone; if you are
  # looking for the role gate, it is here, plus `verify_authorized` in
  # `Api::V1::BaseController`, which makes forgetting to call a policy raise.
  #
  # Belonging to something is not permission to act on it either — edu-safi's
  # lesson: `current_organization` is tenancy, not authorisation. Hence the
  # `own?`/`owner?` predicates in the subclasses ON TOP of these.
  # TWO KINDS OF ADMIN, because there are two front doors.
  #
  # `AdminUser` is the ops console's own table, separate from the mobile `User`
  # by design — correction 16 is that nothing which can credit a wallet exists
  # on a phone that gets shared or lost. Holding an `AdminUser` session IS being
  # an admin; there is no lesser console account, and `AdminUser` has no `role?`
  # at all, so the check must come first or it raises.
  #
  # The mobile branch stays for the API, where an admin is a `User` holding the
  # role.
  def admin?
    return true if user.is_a?(AdminUser)

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
