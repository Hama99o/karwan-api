# Every authenticated API endpoint inherits from this.
#
# Controllers are namespaced BY ROLE below this point — customer/, merchant/,
# courier/ — never one controller branching on `current_user.courier?`.
# Duplication between roles is cheaper than coupling between roles, because
# roles diverge over time and the conditionals never get removed.
class Api::V1::BaseController < ApplicationController
  before_action :authenticate_user!

  # Pundit will not let an action through unless a policy was consulted. This
  # is the guard against edu-safi's most expensive bug: five endpoints where the
  # correct scope existed, was correct, and was never called. A forgotten
  # `authorize` is now a failing request, not a silent hole.
  # Guarded by a PREDICATE, not by `only:`/`except:` action names. Rails
  # validates those names against the controller's defined actions and raises
  # AbstractController::ActionNotFound for any it does not have — so
  # `only: :index` broke every controller without an index action, which is
  # every courier controller (a courier has one job and one offer, not lists).
  #
  # The symptom was an HTML 404 from the exception middleware rather than a
  # useful error, which is what made it worth a note: a routing-shaped 404 that
  # is actually a callback registration failure.
  after_action :verify_authorized, unless: :index_action?
  after_action :verify_policy_scoped, if: :index_action?

  private

  def index_action?
    action_name == "index"
  end
end
