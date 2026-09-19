require "rails_helper"

# ── THE PUBLISHED VOCABULARY MUST BE THE REAL ONE ──────────────────────────
#
# `docs/API_VOCABULARY.md` exists so the mobile repo can diff its own
# declarations against the server's words, after two types called `Role` were
# found with no translation between them and nothing to catch it because
# nothing had ever read the field.
#
# A stale vocabulary list is worse than none, for the same reason a stale
# endpoint list is: somebody diffs against it and gets confident nonsense. So
# it is asserted from both ends — the values the code defines, and whether the
# document still names them.
RSpec.describe "docs/API_VOCABULARY.md" do
  let(:doc) { Rails.root.join("docs/API_VOCABULARY.md").read }

  # The exact lists the document publishes. A change here is a wire change:
  # somebody's `switch (status)` loses a branch, or gains one it ignores.
  VOCABULARIES = {
    "Roles::ALL" => %w[customer courier merchant_owner admin],
    "Roles::MOBILE" => %w[customer courier merchant_owner],
    "Order.statuses" => %w[placed accepted preparing ready picked_up delivered rejected cancelled failed],
    "Trip.statuses" => %w[requested accepted arrived in_progress completed cancelled failed],
    "Order.failure_reasons" => %w[customer_refused nobody_home customer_unreachable wrong_address other],
    "Order.cancellation_reasons" => %w[customer_changed_mind merchant_unavailable no_courier_available duplicate other],
    "ServiceTiers::ALL" => %w[normal premium],
    "VehicleTypes::ALL" => %w[motorbike bicycle car on_foot rishka zarang],
    "WalletEntry.kinds" => %w[commission top_up reimbursement adjustment commission_topup],
    "Order.payment_statuses" => %w[pending collected settled],
    "User::LOCALES" => %w[ps fa en],
    "User::THEMES" => %w[system light dark]
  }.freeze

  def actual(name)
    case name
    when "Roles::ALL" then Roles::ALL.keys
    when "Roles::MOBILE" then Roles::MOBILE.map(&:to_s)
    when "Order.statuses" then Order.statuses.keys
    when "Trip.statuses" then Trip.statuses.keys
    when "Order.failure_reasons" then Order.failure_reasons.keys
    when "Order.cancellation_reasons" then Order.cancellation_reasons.keys
    when "ServiceTiers::ALL" then ServiceTiers::ALL.keys.map(&:to_s)
    when "VehicleTypes::ALL" then VehicleTypes::ALL.keys.map(&:to_s)
    when "WalletEntry.kinds" then WalletEntry.kinds.keys
    when "Order.payment_statuses" then Order.payment_statuses.keys
    when "User::LOCALES" then User::LOCALES
    when "User::THEMES" then User::THEMES
    end.map(&:to_s)
  end

  VOCABULARIES.each do |name, expected|
    it "#{name} still reads #{expected.join(' ')}" do
      expect(actual(name)).to eq(expected),
                              "#{name} changed. This is a WIRE change: update docs/API_VOCABULARY.md " \
                              "and tell the mobile session, which branches on these strings."
    end
  end

  it "names every published value in the document" do
    missing = VOCABULARIES.values.flatten.uniq.reject { |value| doc.include?(value) }

    expect(missing).to be_empty,
                       "docs/API_VOCABULARY.md no longer names: #{missing.join(', ')}. " \
                       "A vocabulary list that omits a value is how a client learns an incomplete one."
  end

  # Published in category D. A code the document does not name is a code the
  # client cannot be expected to have a sentence for.
  it "names every error code in the document" do
    missing = ErrorCodes::ALL.reject { |code| doc.include?(code) }

    expect(missing).to be_empty,
                       "docs/API_VOCABULARY.md does not name: #{missing.join(', ')}. " \
                       "An undeclared code reaches a person as a generic failure."
  end

  # `merchant` is the UI's word, not the server's, and writing it into this
  # document would re-create exactly the confusion the document exists to end.
  it "does not claim a role called `merchant` exists" do
    expect(Roles::ALL.keys).not_to include("merchant")
    expect(doc).to include("There is no role called `merchant`")
  end
end
