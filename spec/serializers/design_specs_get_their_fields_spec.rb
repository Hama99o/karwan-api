require "rails_helper"

# ═══ THE SWEEP POINTED AT THE DESIGN INSTEAD OF THE CODE ═══════════════════
#
# `payload_key_sets_spec` asks *"does the response carry a field nobody asked
# for?"* This asks the other half: **does the screen get every field its own
# SPEC names?** That is how `opening_hours` was found — the Home SPEC named it,
# the list did not serve it, and the screen was blocked on an API nobody had
# asked to change.
#
# ── DERIVED ON BOTH SIDES, WHICH IS WHAT KEEPS IT HONEST ─────────────────
#
# The field list comes from the SPEC files, not from me. But a SPEC also
# backticks dish names, component names and file names, so a bare token list is
# mostly noise. The filter is the other derivation: **a token counts as an API
# field only if some payload in this API actually serves it.** Both ends are
# read from something; neither is a list I typed.
#
# The consequence worth stating: this cannot catch a field the SPEC names that
# NO endpoint serves anywhere — that is a field that does not exist yet, and it
# arrives as a request from the mobile session rather than as a red spec.
#
# ── WHY IT SKIPS RATHER THAN FAILS WITHOUT THE OTHER REPO ────────────────
#
# The SPECs live in `karwan-mobile`. A checkout without it beside this one is a
# legitimate state (CI, a fresh clone), and RSpec reports a skip as PENDING in
# the summary — visible, not silent. Same treatment as `preflight_spec`'s rig
# probe.
RSpec.describe "every design SPEC gets the fields it names", type: :request do
  DESIGN_ROOT = Rails.root.join("../karwan-mobile/docs/design")

  # Which endpoint each screen reads. This mapping is the one thing here that is
  # stated rather than derived, and it is a fact about the product rather than a
  # judgement: the Home screen reads the browse list, the cart reads a quote.
  SCREENS = {
    "customer/home" => { label: "browse list", node: %w[merchants 0] },
    # MERCHANT-DETAIL READS TWO ENDPOINTS, and my first mapping said one. The
    # screen shows the shop AND its menu, so `items`, `currency` and
    # `item_count` come from `/catalog` — they were reported missing because the
    # mapping was wrong, not the payload. The sweep found my own error before it
    # found anybody else's.
    "customer/merchant-detail" => { label: "merchant page and its catalog", node: %w[merchant_and_catalog] },
    "customer/order-tracking" => { label: "order detail", node: %w[order] },
    "customer/cart" => { label: "the quote", node: %w[quote] },
    "customer/addresses" => { label: "the saved pins", node: %w[addresses] },
    "customer/profile" => { label: "the signed-in person", node: %w[user] },
    "customer/account-edit" => { label: "the signed-in person", node: %w[user] },
    "courier/wallet" => { label: "the courier wallet", node: %w[wallet] },
    "courier/verification" => { label: "the courier application", node: %w[registration] },
    "merchant/board" => { label: "the order board", node: %w[board] }
  }.freeze

  # ── A TOKEN IN A DOCUMENT IS NOT A REQUIREMENT ───────────────────────────
  #
  # The extraction reads every backticked name, and a SPEC names fields for two
  # other reasons: to REJECT one, and to describe a state of the API that has
  # since changed. Both showed up on the first run, and both would have been
  # "fixed" by adding a field nobody wants:
  #
  # Named with the reason, so the domain stays derived and anything NOT here
  # has to be judged rather than waved through.
  NOT_A_REQUIREMENT = {
    [ "customer/merchant-detail", "item_count" ] =>
      "the SPEC says `item_count` is NOT SHOWN — it names the field to reject it: " \
      "\"a count is a fact about the menu, not a reason to choose a category\"",
    [ "customer/profile", "verification_status" ] =>
      "served as `courier_verification_status` on /me — the SPEC names the COLUMN, which lives on " \
      "courier_profiles, and the payload names whose status it is. Nil for anybody who is not a courier.",
    [ "customer/account-edit", "avatar" ] =>
      "names the ATTACHMENT, not the payload key. The screen reads /me, which serves `avatar_url`, " \
      "`name`, `phone` and `locale` — all of which it edits; that SPEC writes them as prose headings " \
      "rather than backticks, so the extraction finds nothing to check.",
    [ "customer/addresses", "pin_far_from_road" ] =>
      "NOT SERVED AND NOT A MISTAKE — it is unmeasured for a saved pin. On an order it comes from snap " \
      "distances frozen at quote time; an address has a pin and no route, so answering it means an OSRM " \
      "call per address. Sized and recorded in NOTES.md rather than built: it is a decision about when " \
      "we measure, not a missing field.",
    [ "customer/order-tracking", "eta_minutes" ] =>
      "the SPEC names it to say where it ISN'T — \"`eta_minutes` exists only on the merchant " \
      "serializer\" — in the paragraph explaining what the screen was blocked on. What it ASKS for is " \
      "the opposite of a minute count: \"the arrival time is a RANGE - 13:30 - 13:40 - not a single " \
      "minute\", now served as `arrival_window` {from, to, basis} on the order detail and the track " \
      "payload. Serving `eta_minutes` here would be the precise lie that SPEC rejected.",
    [ "customer/home", "opening_hours" ] =>
      "superseded. The SPEC asks in prose for one line — \"opens at ۸:۰۰\" when the shop is " \
      "closed — and the list now serves `hours_known` + `next_opens_at`, which is that answer. " \
      "A week of rows for twenty merchants is the payload we deliberately did not send."
  }.freeze

  let(:customer) { create(:user, :customer) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(customer).last}" } }
  let!(:merchant) { create(:merchant, is_open: true) }

  # Every key this API serves anywhere — the filter that turns a SPEC's
  # backticks into API fields rather than prose.
  def all_api_keys
    @all_api_keys ||= begin
      keys = Set.new
      order = create(:order, :delivered, customer: customer, merchant: merchant)

      get "/api/v1/public/merchants"
      keys.merge(JSON.parse(response.body).fetch("merchants").first.keys)
      get "/api/v1/public/merchants/#{merchant.id}"
      keys.merge(JSON.parse(response.body).fetch("merchant").keys)
      get "/api/v1/customer/orders/#{order.id}", headers: auth
      keys.merge(JSON.parse(response.body).fetch("order").keys)

      # The universe has to widen with the screens. A field this API serves ONLY
      # on the wallet would otherwise be filtered out as prose and the gap would
      # hide — the filter is what makes the sweep honest and also what could
      # make it blind.
      courier = create(:user, :courier)
      courier_auth = { "Authorization" => "Bearer #{UserSession.issue!(courier).last}" }
      get "/api/v1/courier/wallet", headers: courier_auth
      keys.merge(JSON.parse(response.body).fetch("wallet").keys)
      get "/api/v1/courier/registration", headers: courier_auth
      keys.merge(JSON.parse(response.body).fetch("registration").keys)
      create(:address, user: customer)
      get "/api/v1/customer/addresses", headers: auth
      keys.merge(JSON.parse(response.body).fetch("addresses").first.keys)
      get "/api/v1/me", headers: auth
      keys.merge(JSON.parse(response.body).fetch("user").keys)

      owner = create(:user, :merchant_owner)
      board_merchant = create(:merchant, owner: owner, is_open: true)
      create(:order, :ready, merchant: board_merchant)
      get "/api/v1/merchant/orders",
          headers: { "Authorization" => "Bearer #{UserSession.issue!(owner).last}" }
      keys.merge(JSON.parse(response.body).fetch("orders").first.keys)
      keys
    end
  end

  def payload_for(node)
    case node.first
    when "merchants" then (get "/api/v1/public/merchants"; JSON.parse(response.body).fetch("merchants").first)
    when "merchant" then (get "/api/v1/public/merchants/#{merchant.id}"; JSON.parse(response.body).fetch("merchant"))
    when "merchant_and_catalog"
      get "/api/v1/public/merchants/#{merchant.id}"
      shop = JSON.parse(response.body).fetch("merchant")
      item = create(:catalog_item, catalog_category: create(:catalog_category, merchant: merchant))
      get "/api/v1/public/merchants/#{merchant.id}/catalog"
      catalog = JSON.parse(response.body).fetch("catalogs").first
      shop.merge(catalog).merge(catalog["items"].first || {})
    when "order"
      order = create(:order, :ready, customer: customer, merchant: merchant, courier: create(:user, :courier))
      get "/api/v1/customer/orders/#{order.id}", headers: auth
      JSON.parse(response.body).fetch("order")
    when "quote"
      item = create(:catalog_item, catalog_category: create(:catalog_category, merchant: merchant))
      post "/api/v1/customer/orders/quote",
           params: { order: { merchant_id: merchant.id, delivery_latitude: 34.529,
                              delivery_longitude: 69.161,
                              lines: [ { catalog_item_id: item.id, quantity: 1 } ] } },
           headers: auth
      JSON.parse(response.body).fetch("quote")
    when "addresses"
      create(:address, user: customer)
      get "/api/v1/customer/addresses", headers: auth
      JSON.parse(response.body).fetch("addresses").first
    when "user"
      get "/api/v1/me", headers: auth
      JSON.parse(response.body).fetch("user")
    when "wallet"
      courier = create(:user, :courier)
      get "/api/v1/courier/wallet",
          headers: { "Authorization" => "Bearer #{UserSession.issue!(courier).last}" }
      JSON.parse(response.body).fetch("wallet")
    when "board"
      owner = create(:user, :merchant_owner)
      merchant.update!(owner: owner)
      create(:order, :ready, merchant: merchant, courier: create(:user, :courier))
      get "/api/v1/merchant/orders",
          headers: { "Authorization" => "Bearer #{UserSession.issue!(owner).last}" }
      JSON.parse(response.body).fetch("orders").first
    when "registration"
      applicant = create(:user, :customer)
      create(:courier_profile, user: applicant)
      get "/api/v1/courier/registration",
          headers: { "Authorization" => "Bearer #{UserSession.issue!(applicant).last}" }
      JSON.parse(response.body).fetch("registration")
    end
  end

  def fields_named_by(spec_path)
    File.read(spec_path).scan(/`([a-z][a-z0-9_]*)`/).flatten.uniq
  end

  it "has the design board beside this repo, or every example below is skipped" do
    skip "karwan-mobile is not beside this one" unless DESIGN_ROOT.exist?

    expect(DESIGN_ROOT.glob("**/SPEC.md")).not_to be_empty
  end

  SCREENS.each do |screen, config|
    it "serves #{config[:label]} every API field #{screen}/SPEC.md names" do
      spec_file = DESIGN_ROOT.join(screen, "SPEC.md")
      skip "karwan-mobile is not beside this one" unless spec_file.exist?

      served = payload_for(config[:node]).keys
      wanted = fields_named_by(spec_file) & all_api_keys.to_a

      if wanted.empty?
        skip "#{screen}/SPEC.md names no backticked API field — nothing to check, and asserting " \
             "against an empty set would be the vacuous green this file exists to avoid"
      end

      missing = (wanted - served).reject { |field| NOT_A_REQUIREMENT.key?([ screen, field ]) }
      expect(missing).to be_empty,
                         "#{screen}/SPEC.md reads #{config[:label]} and names #{missing.join(', ')}, " \
                         "which that payload does not carry. This is the opening_hours shape: a screen " \
                         "blocked on the API rather than on itself."
    end
  end
end
