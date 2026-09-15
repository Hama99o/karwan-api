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
  after_action :verify_authorized, except: :index
  after_action :verify_policy_scoped, only: :index
end
