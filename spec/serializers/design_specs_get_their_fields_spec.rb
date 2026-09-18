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
    "customer/order-tracking" => { label: "order detail", node: %w[order] }
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

      expect(wanted).not_to be_empty,
                           "#{screen}/SPEC.md names no field this API serves — the filter matched nothing, " \
                           "so the assertion below would be vacuous"

      missing = (wanted - served).reject { |field| NOT_A_REQUIREMENT.key?([ screen, field ]) }
      expect(missing).to be_empty,
                         "#{screen}/SPEC.md reads #{config[:label]} and names #{missing.join(', ')}, " \
                         "which that payload does not carry. This is the opening_hours shape: a screen " \
                         "blocked on the API rather than on itself."
    end
  end
end
