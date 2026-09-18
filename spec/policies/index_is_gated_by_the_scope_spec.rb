require "rails_helper"

# ── A PREDICATE THAT LOOKS LIKE A GATE AND IS NEVER CONSULTED ────────────────
#
# `Api::V1::BaseController` makes the rule structural:
#
#   after_action :verify_authorized,    unless: :index_action?
#   after_action :verify_policy_scoped, if:     :index_action?
#
# So an index action is gated by `policy_scope`, and `authorize` is not merely
# unnecessary there — the sweep found that NO index action calls it. Which meant
# four policies carried `def index? = true` that Pundit never reached.
#
# **They were not merely dead.** `ApplicationPolicy` denies by default, and says
# so at the top of the file, precisely so a forgotten action refuses rather than
# allows. Each `index? = true` silently opted one resource out of that — with no
# ownership check, unlike the `show?`/`update?` beside it, which are `own?`. The
# day somebody writes `authorize @address` in a listing, the deny-by-default
# design is already disarmed for it and nothing says so.
#
# Deleting them changed no behaviour today and makes that future call fail
# closed, at the moment it is written, which is when its author can decide
# properly. This spec is what keeps one from drifting back, because the reason
# it is wrong is invisible from inside the policy file.
RSpec.describe "index is gated by the scope, not by a predicate" do
  policies = Dir["app/policies/**/*_policy.rb"].map { |f|
    File.basename(f, ".rb").camelize.constantize
  }

  it "finds the policies, so an empty glob cannot pass this vacuously" do
    expect(policies.size).to be >= 8
  end

  it "keeps ApplicationPolicy denying by default" do
    expect(ApplicationPolicy.new(nil, nil).index?).to be false
  end

  it "has no policy overriding index?, because nothing would ever call it" do
    overriders = policies.reject { |k| k == ApplicationPolicy }
                         .select { |k| k.instance_method(:index?).owner == k }

    expect(overriders).to be_empty, <<~MSG
      These policies define `index?`, which Pundit never consults:
        #{overriders.join(', ')}
      An index action is gated by `policy_scope`. Put the rule in `Scope#resolve`
      — a predicate here reads like a gate and guards nothing.
    MSG
  end

  it "still skips verify_authorized for index, which is what makes that true" do
    callbacks = Api::V1::BaseController._process_action_callbacks
                                       .select { |c| c.filter == :verify_authorized }

    expect(callbacks).to be_present
    expect(callbacks.first.instance_variable_get(:@if)).to be_empty
    expect(callbacks.first.instance_variable_get(:@unless)).to be_present
  end
end
