require "rails_helper"

# ── THE DECLARATION MUST BE THE VOCABULARY ─────────────────────────────────
#
# `ErrorCodes` is only worth having if it cannot drift from what the
# controllers actually send. Asserted in BOTH directions, because each catches
# a different mistake:
#
#   emitted but undeclared -> a new refusal reached a person as "something went
#                             wrong" and nobody told the client it existed
#   declared but unemitted -> the published list teaches a client to handle a
#                             code it will never see, and the dead entry makes
#                             the real ones look maintained
RSpec.describe ErrorCodes do
  def emitted
    Dir[Rails.root.join("app/controllers/**/*.rb"), Rails.root.join("app/services/**/*.rb"),
        Rails.root.join("lib/**/*.rb")]
      .flat_map { |file| File.read(file).lines.reject { |l| l =~ /\A\s*#/ } }
      .join
      .scan(/code:\s*"([a-z_]+)"/).flatten.uniq
  end

  it "declares every code the API actually sends" do
    expect(emitted - ErrorCodes::ALL).to be_empty,
                                         "these codes are sent but not declared in ErrorCodes: " \
                                         "#{(emitted - ErrorCodes::ALL).join(', ')}. Declare them with the sentence " \
                                         "a user should see, and tell the mobile session — an undeclared code " \
                                         "reaches a person as a generic failure."
  end

  it "sends every code it declares" do
    expect(ErrorCodes::ALL - emitted).to be_empty,
                                         "declared but never sent: #{(ErrorCodes::ALL - emitted).join(', ')}. " \
                                         "A published list that includes codes nothing emits teaches a client to " \
                                         "handle what it will never see."
  end

  # The pairing that stops both examples above being vacuous. If the scan
  # stopped matching — a changed helper, a symbol instead of a string — it would
  # return [] and `[] - anything` is empty, so BOTH examples would pass while
  # checking nothing at all.
  it "is actually reading codes out of the controllers" do
    expect(emitted.size).to be > 25
    expect(emitted).to include("offer_expired", "outside_service_area", "tier_unavailable")
  end

  it "puts each code in exactly one group" do
    groups = [ ErrorCodes::AUTH, ErrorCodes::OTP, ErrorCodes::RESET, ErrorCodes::ORDERING,
               ErrorCodes::DISPATCH, ErrorCodes::GEOGRAPHY, ErrorCodes::INFRASTRUCTURE ]
    flat = groups.flatten

    expect(flat.uniq).to eq(flat), "a code appears in two groups: #{flat.tally.select { |_, n| n > 1 }.keys.join(', ')}"
    expect(ErrorCodes::ALL.sort).to eq(flat.sort)
  end

  # These two are different answers to different questions and a client that
  # collapses them draws a route to a place we have said we do not serve.
  it "keeps `outside_service_area` and `unroutable` as separate codes" do
    expect(ErrorCodes::GEOGRAPHY).to include("outside_service_area", "unroutable")
    expect(ErrorCodes::GEOGRAPHY.uniq.size).to eq(2)
  end
end
