require "rails_helper"

# ── ONE FIELD, THREE ACTORS' VOCABULARIES ──────────────────────────────────
#
# `Order.cancellation_reasons` is not one list. Traced value by value:
#
#   customer_changed_mind   customers/orders#cancel       the customer
#   no_courier_available    dispatch/job_timeouts_job     the system
#   other                   admin/orders#cancel           an operator
#   merchant_unavailable    nothing, anywhere             unused
#   duplicate               nothing, anywhere             unused
#
# The mobile session read "a customer can express one of five" and was about to
# build a sheet offering the other four. It would have let a customer record
# `no_courier_available` — dispatch reporting on dispatch — and corrupted the
# one number that says whether supply failed.
#
# A NOTE IN `docs/NOTES.md` CANNOT STOP THAT. This can. The gate is the same
# shape the mobile session built for its two `Role` vocabularies: a layer may
# only speak the words that belong to it.
RSpec.describe "Order.cancellation_reasons belongs to one actor at a time" do
  CUSTOMER_MAY_SET = %w[customer_changed_mind].freeze
  SYSTEM_SETS      = %w[no_courier_available].freeze
  OPERATOR_SETS    = %w[other].freeze
  # Set by nothing. Kept as an explicit list so that USING one is a deliberate
  # act that fails this spec and forces the decision, rather than a quiet
  # assignment that defines the value's meaning forever.
  SET_BY_NOTHING   = %w[merchant_unavailable duplicate].freeze

  def code_without_comments(glob)
    Dir[Rails.root.join(glob)].map do |file|
      File.read(file).lines.reject { |line| line =~ /\A\s*#/ }.join
    end.join("\n")
  end

  # Catches a value added to the enum with nobody deciding whose word it is.
  it "accounts for every value in the enum" do
    accounted = (CUSTOMER_MAY_SET + SYSTEM_SETS + OPERATOR_SETS + SET_BY_NOTHING).sort

    expect(accounted).to eq(Order.cancellation_reasons.keys.sort),
                         "a cancellation reason was added or removed without deciding which actor owns it. " \
                         "Update this spec and docs/API_VOCABULARY.md together — a client branches on these."
  end

  it "lets no customer-facing endpoint set a reason that is not the customer's own" do
    found = code_without_comments("app/controllers/api/v1/customers/**/*.rb")
              .scan(/cancellation_reason:\s*:(\w+)/).flatten.uniq

    expect(found - CUSTOMER_MAY_SET).to be_empty,
                                        "a customer endpoint sets #{(found - CUSTOMER_MAY_SET).join(', ')}. " \
                                        "A customer may not assert the system's or an operator's finding — " \
                                        "`no_courier_available` is dispatch reporting on dispatch."
  end

  # The pairing that stops the example above being vacuous: if the scan ever
  # matched nothing at all — a rename, a move, a changed spelling — `found`
  # would be empty and `[] - anything` is empty, so it would pass while
  # checking nothing.
  it "is actually finding the assignment it claims to police" do
    found = code_without_comments("app/controllers/api/v1/customers/**/*.rb")
              .scan(/cancellation_reason:\s*:(\w+)/).flatten

    expect(found).to include("customer_changed_mind"),
                     "the scan found no cancellation_reason assignment in the customer controllers at all, " \
                     "so the example above cannot fail. Fix the scan, not this expectation."
  end

  it "keeps the unused values unused, so nothing defines their meaning by accident" do
    app = code_without_comments("app/**/*.rb")

    SET_BY_NOTHING.each do |value|
      expect(app).not_to match(/cancellation_reason:\s*:#{value}\b/),
                         "`#{value}` is now set somewhere. It had no meaning until this moment and now it has " \
                         "one — decide it on purpose: who may claim it, and what does a report counting it mean?"
    end
  end
end
