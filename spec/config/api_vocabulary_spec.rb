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
    "Order.failure_reasons" => %w[customer_refused nobody_home customer_unreachable wrong_address other fake_note],
    "Order.cancellation_reasons" => %w[customer_changed_mind merchant_unavailable no_courier_available duplicate other],
    # TWO LISTS, AND THE DIFFERENCE IS THE POINT. The column carries
    # `no_answer`, which the timeout job writes about a shop that never replied;
    # the board may not send it. A merchant-side picker built from the wrong one
    # lets a shop label its own refusal "we were never asked".
    "Order.rejection_reasons" => %w[out_of_stock too_busy closing other no_answer],
    "Order::MERCHANT_REJECTION_REASONS" => %w[out_of_stock too_busy closing other],
    "ServiceTiers::ALL" => %w[normal premium],
    "VehicleTypes::ALL" => %w[motorbike bicycle car on_foot rishka zarang],
    "WalletEntry.kinds" => %w[commission top_up reimbursement adjustment commission_topup],
    "Order.payment_statuses" => %w[pending collected settled],
    "User::LOCALES" => %w[ps fa en],
    "User::THEMES" => %w[system light dark],
    # Found unpinned by the enum sweep below, 24 Sept 2026 — each read by the
    # app, so a rename was a silent client break with every spec green.
    "CourierProfile.verification_statuses" => %w[pending approved rejected suspended needs_more],
    "CatalogItemOption.selection_types" => %w[single multiple],
    "Merchant.statuses" => %w[pending active suspended rejected lead],
    "DeviceToken.platforms" => %w[android ios],
    "Trip.failure_reasons" => %w[passenger_no_show passenger_unreachable passenger_refused unsafe other fake_note],
    "Trip.cancellation_reasons" => %w[passenger_changed_mind courier_unavailable no_courier_available duplicate other]
  }.freeze

  # ── EVERY ENUM IS EITHER A WIRE VOCABULARY OR SAYS WHY NOT ──────────────
  #
  # The list above was typed, so it could only pin what somebody thought of.
  # On 2026-09-24 the sweep below found `verification_status` (the app
  # branches on `needs_more`) and `selection_type` (it decides how a menu's
  # choices render) on the wire, read by karwan-mobile, in neither the list
  # nor the document. Every enum any model defines is enumerated here; each
  # is pinned above, or named below with why it never reaches a client, or
  # which pinned list it shares its values with.
  ENUMS_NOT_PINNED_HERE = {
    "AuditLog.actor_roles" => "the same four values as Roles::ALL, pinned above",
    "StatusTransition.actor_roles" => "the same four values as Roles::ALL, pinned above",
    "UserRole.roles" => "the same four values as Roles::ALL, pinned above",
    "UserSession.active_roles" => "the same four values as Roles::ALL, pinned above",
    "User.last_active_roles" => "the same four values as Roles::ALL, pinned above",
    "Order.cancelled_by_roles" => "the same four values as Roles::ALL; served as ended_reason.ended_by",
    "Trip.cancelled_by_roles" => "the same four values as Roles::ALL; served as ended_reason.ended_by",
    "CourierProfile.vehicle_types" => "the same values as VehicleTypes::ALL, pinned above",
    "PricingRate.vehicle_types" => "the same values as VehicleTypes::ALL, pinned above",
    "Trip.vehicle_types" => "the same values as VehicleTypes::ALL, pinned above",
    "Order.courier_vehicle_types" => "the same values as VehicleTypes::ALL, pinned above",
    "Order.service_tiers" => "the same values as ServiceTiers::ALL, pinned above",
    "Trip.service_tiers" => "the same values as ServiceTiers::ALL, pinned above",
    "Trip.payment_statuses" => "the same values as Order.payment_statuses, pinned above",
    "Order.payment_methods" => "cash only in v0, and in no mobile payload",
    "Trip.payment_methods" => "cash only in v0, and in no mobile payload",
    "Offer.statuses" => "internal to dispatch; no serializer sends an offer's status (docs §C)",
    "User.statuses" => "a suspended account is refused at authentication; no payload branches on it",
    "CatalogItem.size_classes" => "set in the console only; drives dispatch, never sent to the app",
    "Order.required_size_classes" => "the same values as CatalogItem.size_classes; dispatch-internal",
    "PricingRate.audiences" => "console only",
    "Setting.value_types" => "console only; /public/app_config sends typed values, not the type"
  }.freeze

  def actual(name)
    case name
    when "Roles::ALL" then Roles::ALL.keys
    when "Roles::MOBILE" then Roles::MOBILE.map(&:to_s)
    when "Order.statuses" then Order.statuses.keys
    when "Trip.statuses" then Trip.statuses.keys
    when "Order.failure_reasons" then Order.failure_reasons.keys
    when "Order.cancellation_reasons" then Order.cancellation_reasons.keys
    when "Order.rejection_reasons" then Order.rejection_reasons.keys
    when "Order::MERCHANT_REJECTION_REASONS" then Order::MERCHANT_REJECTION_REASONS
    when "ServiceTiers::ALL" then ServiceTiers::ALL.keys.map(&:to_s)
    when "VehicleTypes::ALL" then VehicleTypes::ALL.keys.map(&:to_s)
    when "WalletEntry.kinds" then WalletEntry.kinds.keys
    when "Order.payment_statuses" then Order.payment_statuses.keys
    when "User::LOCALES" then User::LOCALES
    when "User::THEMES" then User::THEMES
    else
      model, plural = name.split(".")
      model.constantize.defined_enums.fetch(plural.singularize).keys
    end.map(&:to_s)
  end

  it "accounts for every enum any model defines" do
    Rails.application.eager_load!
    defined = ApplicationRecord.descendants.reject(&:abstract_class?).flat_map do |model|
      model.defined_enums.keys.map { |attr| "#{model.name}.#{attr.pluralize}" }
    end.uniq
    enum_keys = VOCABULARIES.keys.grep(/\A[A-Z]\w*\.[a-z_]+\z/)

    unaccounted = defined - enum_keys - ENUMS_NOT_PINNED_HERE.keys
    stale = (ENUMS_NOT_PINNED_HERE.keys + enum_keys) - defined

    expect(unaccounted).to be_empty,
                           "these enums are neither pinned as a wire vocabulary nor said to stay off the wire: " \
                           "#{unaccounted.join(', ')}"
    expect(stale).to be_empty, "these name enums that no longer exist: #{stale.join(', ')}"
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

  # GUARDS THE PUBLISHED NUMBER, and makes the method reachable. It was added
  # tonight, documented in API_VOCABULARY.md as "returns the 25", and called by
  # nothing — a built-and-unreachable created during an audit for exactly that.
  # `bin/callers` reported it within the hour.
  it "reachable_in_normal_use returns the count the document promises" do
    codes = ErrorCodes.reachable_in_normal_use

    # ── READ FROM THE DOCUMENT, NOT TYPED TWICE ────────────────────────────
    #
    # This used to assert a literal and tell the reader to go and update the
    # prose. Adding one code moved the code's count to 52 while the document
    # still said 51, and every example here stayed green — the spec was
    # checking the number against itself and merely NAMING the document.
    #
    # The number now comes OUT of the document, so the two cannot drift: if the
    # prose is stale the count will not match, and the failure says which.
    documented = doc[/returns the \*\*(\d+)\*\* that are not OTP/, 1]&.to_i

    expect(documented).to be_present, "the document no longer states how many codes are reachable"
    expect(codes.size).to eq(documented),
                          "the document says #{documented} codes are reachable in normal use; this returns #{codes.size}. " \
                          "If that is right, update docs/API_VOCABULARY.md in the same commit — the mobile " \
                          "session sizes its translation work from that number."
    expect(codes).not_to include(*ErrorCodes::OTP)
    expect(codes).to include("offer_expired", "not_cancellable", "outside_service_area")
  end

  # The gap between the column and the board, asserted rather than left to two
  # literal lists that could drift into agreement. If a later value is added to
  # the enum for the system's use, this fails until somebody decides which side
  # of the line it is on.
  it "keeps no_answer out of what a merchant may send" do
    expect(Order.rejection_reasons.keys - Order::MERCHANT_REJECTION_REASONS).to eq(%w[no_answer])
    expect(Order::MERCHANT_REJECTION_REASONS - Order.rejection_reasons.keys).to be_empty,
                                                                               "the board offers a reason the column cannot store"
  end

  # ── SECTION C'S CLAIM, CHECKED RATHER THAN BELIEVED ──────────────────────
  #
  # The value lists were always asserted. What rotted was the PROSE about where
  # a vocabulary appears — and prose is what a reader acts on. Three rows of
  # "NEVER MET" were wrong at once: `preferred_theme` is serialized AND accepted
  # as input, `accepted_job_kinds` and `job_kind` appear in four payloads, and a
  # merchant sees its own `status`.
  #
  # That is the most damaging place in this document to be stale. Section C
  # exists to tell a mobile session where no server word exists yet, so a wrong
  # entry sends somebody to invent a vocabulary that is already on the wire —
  # the exact `Role` mismatch this file was written after.
  #
  # ── WHAT THIS CAN AND CANNOT CHECK, STATED ───────────────────────────────
  #
  # A vocabulary is "on the wire" if its attribute name appears in a serializer
  # or in an API controller that builds a payload inline. That works only for a
  # DISTINCTIVE name. `status` and `cancellation_reason` appear all over for
  # unrelated reasons, so those rows are named below as unverifiable here and
  # are checked by hand — a gate that quietly skipped them would be worse than
  # one that says which it skipped.
  # THE TABLE ROWS ONLY, not the prose around them. The first version sliced the
  # whole section and immediately reported `theme` and `courier job kinds` as
  # live claims — because the paragraph explaining that those rows HAD been
  # wrong names them. A gate that cannot tell a claim from a description of a
  # retired claim will fail every time somebody writes down what was fixed,
  # which teaches people to stop writing it down.
  let(:section_c) do
    section = doc[/## C · NEVER MET.*?(?=\n## |\n---)/m].to_s
    section.lines.select { |line| line.start_with?("|") }.join
  end

  let(:payload_source) do
    Dir[Rails.root.join("app/serializers/**/*.rb"), Rails.root.join("app/controllers/api/**/*.rb")]
      .map { |file| File.read(file) }.join("\n")
  end

  # label as it appears in the document => the attribute a payload would carry.
  let(:checkable) do
    {
      "theme" => "preferred_theme",
      "courier job kinds" => "accepted_job_kinds",
      "payment status" => "payment_status"
    }
  end

  # Rows whose attribute name is too common to search for. Named, with why.
  let(:by_hand) do
    {
      "order cancellation reason, as an INPUT" => "`cancellation_reason` is written by the controller as a " \
                                                  "hard-coded value; the token appearing proves nothing either way",
      "trip cancellation reason" => "same token as the row above",
      "offer status" => "`status` appears in most payloads for unrelated models"
    }
  end

  it "lists no vocabulary as NEVER MET that is in fact on the wire" do
    expect(section_c).to be_present, "section C is not in the document — every check below is vacuous"

    wrong = checkable.select do |label, attribute|
      section_c.include?(label) && payload_source.include?(attribute)
    end

    expect(wrong).to be_empty,
                     "#{wrong.keys.join(', ')} — listed as never having crossed the wire, and the attribute is " \
                     "in a payload. A mobile session reading section C will invent a word that already exists."
  end

  # The other direction: a vocabulary genuinely NOT on the wire must still be
  # somewhere in the document, or it is a word nobody has been warned about.
  it "still warns about the vocabulary that really has not crossed" do
    expect(payload_source).not_to include("payment_status"),
                                  "payment_status has reached a payload — move it out of section C"
    expect(doc).to include("payment status")
  end

  it "names every row it cannot check, rather than skipping it silently" do
    expect(by_hand.values).to all(be_present)
    by_hand.each_key { |label| expect(section_c).to include(label), "#{label} is no longer in section C" }
  end

  # `merchant` is the UI's word, not the server's, and writing it into this
  # document would re-create exactly the confusion the document exists to end.
  it "does not claim a role called `merchant` exists" do
    expect(Roles::ALL.keys).not_to include("merchant")
    expect(doc).to include("There is no role called `merchant`")
  end
end
