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
#   3. every `code:` site that is NOT a literal is ACCOUNTED FOR — keyed by
#      FILE AND EXPRESSION, and resolved to the VALUES it can send, each of
#      which must be declared.
#
# ── 3 USED TO BE BY NAME ONLY, AND TWO THINGS WALKED THROUGH IT ──────────
#
# ACCOUNTED_FOR mapped an expression to a LABEL: `"conflict.to_s" =>
# "Eligibility::REASONS"`. A label is a claim, not a check, so:
#   - on 24 Sept 2026 `job_taken` went out through `conflict.to_s` and every
#     example here stayed green (it is now a literal — see NOTES);
#   - `no_courier_profile` has gone out for weeks as a POSITIONAL argument to
#     `render_courier_error`, a site labelled "a forwarded parameter — not a
#     vocabulary". It was declared nowhere.
# Now each site says where its values come from IN CODE, and the values are
# asserted; a new site, or an old expression in a new file, fails until it does.
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

  # Every non-literal `code:` SITE, as "path: expression" — per file, because
  # the same expression in a second controller may carry a different
  # vocabulary, and a name-only key would pass it on the first one's account.
  def dynamic_sites
    Dir[API.join("**/*.rb")].sort.flat_map do |file|
      body = strip_comments([ file ])
      rel = Pathname(file).relative_path_from(API).to_s
      body.scan(/\bcode:[ \t]*([A-Za-z_][A-Za-z0-9_.\[\]:()]*)/).flatten
          .map { |expr| "#{rel}: #{balance(expr)}" }
    end.uniq
  end

  # Every non-literal `code:` whose value is not a string literal, normalised to the bare
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

  # The codes a method can RETURN, read from its body: every `:symbol` it
  # returns and every "string" it yields. Used where the vocabulary is a
  # method rather than a hash — and it fails loudly on an empty read, so a
  # renamed method cannot quietly resolve to nothing.
  def returned_by(file, method)
    body = File.read(Rails.root.join(file))[/def (self\.)?#{method}\b.*?\n  end/m]
    raise "could not read #{method} in #{file}" if body.nil?

    lines = body.lines.reject { |l| l =~ /\A\s*#/ }.join
    (lines.scan(/return :([a-z_]+)/).flatten + lines.scan(/"([a-z_]+)"/).flatten).uniq
  end

  # Each SITE, and the values it can send — resolved in code. `:not_a_code`
  # (with the reason as the second element) is for a `code:` key that is not a
  # wire vocabulary at all.
  def accounted_for
    {
      "v1/me_controller.rb: deletion.reason.to_s" => Users::AccountDeletion::REASONS.keys.map(&:to_s),
      "v1/customers/orders_controller.rb: error_code_for(e)" =>
        returned_by("app/controllers/api/v1/customers/orders_controller.rb", "error_code_for"),
      "v1/couriers/offers_controller.rb: eligibility.reason.to_s" => Dispatch::Eligibility::REASONS.keys.map(&:to_s),
      "v1/couriers/offers_controller.rb: conflict.to_s" => Dispatch::Eligibility::REASONS.keys.map(&:to_s),
      "v1/auth/sessions_controller.rb: refusal.to_s" => returned_by("app/models/user_session.rb", "role_refusal"),
      "v1/auth/registrations_controller.rb: refusal.to_s" => returned_by("app/models/user_session.rb", "role_refusal"),
      # THE ONE THE LABEL HID. A forwarded parameter whose callers pass wire
      # codes as positional literals — so its values are those literals.
      "v1/couriers/base_controller.rb: code" => File.read(API.join("v1/couriers/base_controller.rb"))
                                                     .scan(/render_courier_error\([^)]*?,\s*"([a-z_]+)"\)/).flatten.uniq,
      "v1/auth/otp_controller.rb: code" => [ :not_a_code, "the OTP digits handed to the SMS body — not a wire code" ],
      "v1/auth/password_resets_controller.rb: params[:code]" => [ :not_a_code, "a reset code the user TYPED — an input" ],
      "v1/auth/sessions_controller.rb: params[:code]" => [ :not_a_code, "an OTP the user TYPED — an input" ]
    }
  end

  def vocabulary_sites
    accounted_for.reject { |_site, values| values.first == :not_a_code }
  end

  it "declares every literal code the API sends" do
    expect(literal_codes - ErrorCodes::ALL).to be_empty,
                                               "sent but not declared: #{(literal_codes - ErrorCodes::ALL).join(', ')}"
  end

  # "Sent" now includes what the dynamic sites RESOLVE to, rather than a list
  # typed beside them — the typed list is how a code can be declared, "sent",
  # and never actually leave the building.
  it "sends every code it declares" do
    from_sources = vocabulary_sites.values.flatten.uniq

    expect(ErrorCodes::ALL - literal_codes - from_sources).to be_empty,
                                                              "declared but never sent: " \
                                                              "#{(ErrorCodes::ALL - literal_codes - from_sources).join(', ')}"
  end

  # THE ONE THAT WOULD HAVE CAUGHT THE MISS — per site, not per name.
  it "accounts for every `code:` site that is not a literal" do
    unaccounted = dynamic_sites - accounted_for.keys

    expect(unaccounted).to be_empty,
                           "these `code:` sites are not accounted for: #{unaccounted.join(', ')}. " \
                           "Each one puts words on the wire that no grep for `code: \"…\"` can see. Say in " \
                           "accounted_for where its values come from IN CODE, or this file is certifying a " \
                           "vocabulary it cannot read."
  end

  # Found a dead entry on its first run: the name-only map listed `nil` ("the
  # default in render_unprocessable_entity's signature") for a site that no
  # longer exists — and nothing could notice, because nothing checked.
  it "has no stale entry — every accounted site still exists" do
    expect(accounted_for.keys - dynamic_sites).to be_empty
  end

  # BY VALUE. Every word each dynamic site can put on the wire is declared.
  it "declares every value a dynamic site can send" do
    vocabulary_sites.each do |site, values|
      expect(values).not_to be_empty, "#{site} resolved to no values — the resolver is reading nothing"
      undeclared = values - ErrorCodes::ALL
      expect(undeclared).to be_empty, "#{site} can send undeclared: #{undeclared.join(', ')}"
    end
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
