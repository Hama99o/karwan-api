require "rails_helper"

# ── THE DECLARATION MUST BE THE VOCABULARY ─────────────────────────────────
#
# `ErrorCodes` is only worth having if it cannot drift from what the API
# actually sends.
#
# ── AND THE FIRST VERSION OF THIS SPEC CERTIFIED A HALF-TRUTH ──────────────
#
# It scanned for `code: "a_literal"` and nothing else, so it reported a complete
# vocabulary of 35 while **twenty-six more** reached clients from expressions:
# `code: deletion.reason.to_s`, `code: error_code_for(e)`,
# `code: eligibility.reason.to_s`, `code: refusal.to_s`. Fourteen of those are
# the reasons a courier may not take a job — met in an ordinary week.
#
# The mobile session reported five of them. The instrument written to stop this
# exact drift had the same blind spot `bin/callers` had with dynamic dispatch,
# and it is worse than no instrument, because it certified the rest as covered.
#
# So this file now asserts THREE things, and the third is the one that matters:
#   1. every literal code is declared
#   2. every declared code is really sent
#   3. every `code:` site that is NOT a literal is ACCOUNTED FOR BY NAME —
#      a new one fails here until somebody says where its words come from
RSpec.describe ErrorCodes do
  API = Rails.root.join("app/controllers/api").freeze

  def strip_comments(files)
    files.map { |file| File.read(file).lines.reject { |l| l =~ /\A\s*#/ }.join }.join("\n")
  end

  def api_source
    strip_comments(Dir[API.join("**/*.rb")])
  end

  # WIDER than the dynamic scan on purpose. `forbidden` and `unauthorized` come
  # from `application_controller`, and `pending_migration` from
  # `lib/middleware` — a scan limited to `app/controllers/api` reported those
  # five as "declared but never sent" while they are sent on every bad request.
  def literal_codes
    strip_comments(Dir[Rails.root.join("app/controllers/**/*.rb"),
                       Rails.root.join("app/services/**/*.rb"),
                       Rails.root.join("lib/**/*.rb")])
      .scan(/code:\s*"([a-z_]+)"/).flatten.uniq
  end

  # Every `code:` whose value is not a string literal, normalised to the bare
  # expression so the set is comparable.
  def dynamic_expressions
    # THE CAPTURE HAS BEEN WRONG TWICE, both times producing a confident list.
    # `code:\s*([^"\n]…)` let `\s*` match nothing so the class ate the SPACE
    # and every literal came back as an expression. Adding `(?!")` did not fix
    # it: `[ \t]*` simply BACKTRACKED to zero width, the lookahead then saw a
    # space rather than the quote, and it passed anyway.
    #
    # Requiring the first captured character to be an identifier character is
    # what actually works — a literal begins with `"`, which cannot match, and
    # backtracking to zero width leaves a space, which also cannot match.
    api_source.scan(/\bcode:[ \t]*([A-Za-z_][A-Za-z0-9_.\[\]:()]*)/).flatten
              .map { |expr| balance(expr) }.uniq
  end

  # `error_code_for(e))` — the class has to allow `)` so that `f(x)` survives,
  # which means it also swallows the CALLER's closing paren. Drop trailing
  # parens until the expression balances, rather than assuming a fixed shape.
  def balance(expr)
    expr = expr[0..-2] while expr.count(")") > expr.count("(")
    expr
  end

  # Each expression, and what it resolves to. An entry here is a claim that
  # somebody looked; `nil` means "not a wire code at all" with the reason.
  ACCOUNTED_FOR = {
    "deletion.reason.to_s" => "Users::AccountDeletion::REASONS — me#destroy, 422",
    "error_code_for(e)" => "the case in customers/orders_controller#error_code_for",
    "eligibility.reason.to_s" => "Dispatch::Eligibility::REASONS — offers#create",
    "conflict.to_s" => "Dispatch::Eligibility::REASONS — offers, combination conflict",
    "refusal.to_s" => "UserSession.role_refusal — the role_request body",
    "code" => "a forwarded parameter (couriers/base_controller, otp) — not a vocabulary",
    "nil" => "the default in render_unprocessable_entity's signature",
    "params[:code]" => "an OTP or reset code the user TYPED — an input, not a refusal"
  }.freeze

  it "declares every literal code the API sends" do
    expect(literal_codes - ErrorCodes::ALL).to be_empty,
                                               "sent but not declared: #{(literal_codes - ErrorCodes::ALL).join(', ')}"
  end

  it "sends every code it declares" do
    from_sources = ErrorCodes::ACCOUNT_DELETION + ErrorCodes::ELIGIBILITY +
                   %w[not_a_mobile_role item_unavailable invalid_options empty_cart
                      no_vehicle_for_this_order cannot_price_order merchant_unavailable]

    expect(ErrorCodes::ALL - literal_codes - from_sources).to be_empty,
                                                              "declared but never sent: " \
                                                              "#{(ErrorCodes::ALL - literal_codes - from_sources).join(', ')}"
  end

  # THE ONE THAT WOULD HAVE CAUGHT THE MISS.
  it "accounts for every `code:` that is not a literal" do
    unaccounted = dynamic_expressions - ACCOUNTED_FOR.keys

    expect(unaccounted).to be_empty,
                           "these `code:` expressions are not accounted for: #{unaccounted.join(', ')}. " \
                           "Each one puts words on the wire that no grep for `code: \"…\"` can see. Say where " \
                           "they come from in ACCOUNTED_FOR and declare them in ErrorCodes, or this file is " \
                           "certifying a vocabulary it cannot read."
  end

  it "is actually reading both kinds out of the controllers" do
    expect(literal_codes.size).to be > 25
    expect(dynamic_expressions).to include("deletion.reason.to_s", "error_code_for(e)")
  end

  # The declared groups are copies, kept readable on purpose. These assert the
  # copies still match the sources they were copied from.
  it "matches Users::AccountDeletion::REASONS" do
    expect(ErrorCodes::ACCOUNT_DELETION).to match_array(Users::AccountDeletion::REASONS.keys.map(&:to_s))
  end

  it "matches Dispatch::Eligibility::REASONS" do
    expect(ErrorCodes::ELIGIBILITY).to match_array(Dispatch::Eligibility::REASONS.keys.map(&:to_s))
  end

  it "matches what customers/orders_controller#error_code_for can return" do
    body = File.read(API.join("v1/customers/orders_controller.rb"))[/def error_code_for.*?\n  end/m]
    returned = body.to_s.lines.reject { |l| l =~ /\A\s*#/ }.join.scan(/"([a-z_]+)"/).flatten

    expect(returned).not_to be_empty, "the scan found no codes in error_code_for; fix the scan"
    expect(returned - ErrorCodes::ALL).to be_empty,
                                          "error_code_for returns undeclared: #{(returned - ErrorCodes::ALL).join(', ')}"
  end

  it "puts each code in exactly one group" do
    flat = [ ErrorCodes::AUTH, ErrorCodes::OTP, ErrorCodes::RESET, ErrorCodes::ORDERING,
             ErrorCodes::DISPATCH, ErrorCodes::ACCOUNT_DELETION, ErrorCodes::ELIGIBILITY,
             ErrorCodes::MERCHANT_SELF_SERVICE, ErrorCodes::GEOGRAPHY,
             ErrorCodes::INFRASTRUCTURE ].flatten

    expect(flat.uniq).to eq(flat), "a code is in two groups: #{flat.tally.select { |_, n| n > 1 }.keys.join(', ')}"
    expect(ErrorCodes::ALL.sort).to eq(flat.sort)
  end

  it "keeps `outside_service_area` and `unroutable` separate" do
    expect(ErrorCodes::GEOGRAPHY).to contain_exactly("outside_service_area", "unroutable")
  end
end
