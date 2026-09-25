# Deny by default. Every predicate is false until a subclass says otherwise, so
# a policy that forgets an action refuses it rather than allowing it.
#
# ── A POLICY ANSWERS "MAY THIS PERSON ACT ON THIS", NOT "IS IT TOO LATE" ──────
#
# Whose thing it is, and which role may touch it, belong here. Whether its
# STATE still allows the act belongs to the state machine (`transition_to!`),
# and the endpoint turns that into a refusal a person can read, such as
# `not_cancellable`. A policy that also checks state turns an explanation into
# a bare 403 at the worst moment: a customer tapping cancel a second too late is
# told "forbidden" instead of "the order has moved on". Found 25 Sept 2026:
# the food door's cancel did exactly that, while the ride door's cancel,
# designed first from "what does the person see when it's too late?", did not
# (docs/NOTES.md).
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
