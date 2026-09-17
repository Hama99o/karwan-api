require "rails_helper"

# ═══ EVERY AUTHENTICATED API ROUTE REFUSES THE WRONG CALLER ════════════════
#
# CLAUDE.md, correction 11: "a controller without a request spec covering both
# the happy path and the forbidden path is not done." On 2026-09-17 that was
# measured across the API rather than assumed, and the four numbers were:
# **53 protected actions, 21 with a forbidden-path example, 0 vacuous, 32 with
# none at all.** Not one boundary was found broken — they were found *unwatched*,
# which is the state that becomes a broken one silently.
#
# `intervention_authorization_spec.rb` had already solved this shape for the
# ops console by deriving its domain from the router. This is that spec's twin
# for the mobile API, and it exists rather than 32 hand-written examples for one
# reason: **a hand-written list does not grow a row when somebody adds a route.**
# The 32 were not carelessness; they were the arithmetic of a list maintained by
# hand against a router that changes.
#
# ── WHY THE DOMAIN IS THE CLASS HIERARCHY ──────────────────────────────────
#
# The eighth shape in docs/TESTING.md is a correct, complete instrument pointed
# at a domain somebody else chose. Filtering by path prefix would be exactly
# that — I would be deciding which namespaces count, and a namespace I forgot
# would be silently outside the instrument while it reported green.
#
# So the domain is derived from what the code itself declares:
# `Api::V1::PublicController`'s own comment says "this endpoint needs no login"
# is a visible choice in the class hierarchy. Inheriting from
# `Api::V1::BaseController` is therefore the declaration of "this needs a
# session", and it is what this spec sweeps. The controllers OUTSIDE that
# hierarchy are asserted against a named list below, so a new unauthenticated
# controller cannot appear without this spec going red.
#
# ── WHAT THIS SPEC CANNOT SEE, stated so it is not read as more ───────────
#
# It asserts **refusal**, at the layer the client actually reads: the status
# code and the error payload. It says nothing whatever about what a SUCCESSFUL
# response carries.
#
# Those are different failures. A scope can be correct at the model, correct in
# the controller, and still hand the wrong fields to the wrong caller in the
# serializer — and a 200 that leaks another courier's rows is invisible to every
# example below, all of which would be green. Per-endpoint tenancy examples are
# what cover that (`wallet_spec.rb`'s "never shows another courier's entries",
# and its siblings), and they must assert at the serializer's layer too: a
# `view :detailed` field is not proven by a model assertion, because a `list`
# render does not carry it.
#
# So: this sweep proves nobody gets IN. It does not prove that what comes OUT
# belongs to the caller.
RSpec.describe "every authenticated API route refuses the wrong caller", type: :request do
  # ── The domain, derived twice: routes → controller class → hierarchy ──────
  GUARDED_API_ROUTES = Rails.application.routes.routes.filter_map { |route|
    controller = route.defaults[:controller].to_s
    next unless controller.start_with?("api/v1/")

    klass = "#{controller}_controller".camelize.safe_constantize
    next unless klass&.<(Api::V1::BaseController)

    path = route.path.spec.to_s.sub("(.:format)", "")
    { verb: route.verb.to_s.gsub(/[^A-Z]/, ""),
      spec: path,
      # Auth is refused before anything is looked up, so the ids need not exist.
      # A 404 here instead of a 401 would itself be the finding: it would mean
      # the record was fetched before the caller was identified.
      path: path.gsub(":kind", "delivery").gsub(/:[a-z_]+/, "1"),
      controller: controller,
      action: route.defaults[:action].to_s }
  }.uniq { |r| "#{r[:verb]} #{r[:spec]}" }.freeze

  # The API controllers that deliberately do NOT require a session. Named, so
  # that adding a new one is a decision somebody makes on purpose.
  OPEN_BY_DESIGN = %w[
    api/v1/auth/otp api/v1/auth/password_resets api/v1/auth/registrations
    api/v1/auth/sessions api/v1/public/app_config api/v1/public/merchant_categories
    api/v1/public/merchant_kinds api/v1/public/merchants
  ].freeze

  def json
    JSON.parse(response.body)
  rescue JSON::ParserError
    {}
  end

  it "found the routes to sweep" do
    expect(GUARDED_API_ROUTES.size).to be >= 50,
                                       "the router yielded #{GUARDED_API_ROUTES.size} guarded routes — the derivation is broken, " \
                                       "and every example below would be sweeping nothing"
  end

  # THE ANTI-DRIFT HALF. Without this, a new controller inheriting from
  # ApplicationController instead of BaseController is simply outside the sweep
  # and nothing goes red.
  it "accounts for every API controller, guarded or deliberately open" do
    all = Rails.application.routes.routes.filter_map { |r|
      c = r.defaults[:controller].to_s
      c.start_with?("api/v1/") ? c : nil
    }.uniq

    unaccounted = all - GUARDED_API_ROUTES.map { |r| r[:controller] }.uniq - OPEN_BY_DESIGN

    expect(unaccounted).to be_empty,
                           "these API controllers neither require a session nor are listed as open by design: " \
                           "#{unaccounted.join(', ')}. If one is meant to be public, add it to OPEN_BY_DESIGN " \
                           "and say why; otherwise it is an unauthenticated endpoint."
  end

  # ── 1 · NO TOKEN ─────────────────────────────────────────────────────────
  describe "with no token at all" do
    GUARDED_API_ROUTES.each do |route|
      it "refuses #{route[:verb]} #{route[:spec]}" do
        public_send(route[:verb].downcase, route[:path])

        expect(response).to have_http_status(:unauthorized),
                            "#{route[:controller]}##{route[:action]} answered #{response.status} to an " \
                            "anonymous caller. A 404 here means the record was looked up before the caller " \
                            "was identified; a 2xx means there is no boundary."
      end
    end
  end

  # ── 2 · A REAL USER HOLDING ONLY THE CUSTOMER ROLE ───────────────────────
  #
  # The half that matters more. A token is easy to get — anyone can register —
  # so "signed in" is not "entitled". This drives every courier and merchant
  # route with a genuine, valid session belonging to somebody who holds neither
  # role, which is precisely the caller a leaked namespace would serve.
  describe "signed in as a plain customer" do
    let(:customer) { create(:user, :customer) }
    let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(customer).last}" } }

    # DERIVED FROM THE GATE, NOT FROM THE PATH. The first draft of this spec
    # selected on the `api/v1/couriers/` path prefix and planted four false
    # failures on `couriers/registrations`, which is **deliberately** not under
    # `Couriers::BaseController`: that base requires an APPROVED profile, and an
    # applicant has none, so inheriting it would make applying impossible for
    # exactly the people who need to apply. A plain customer POSTing it is the
    # only way a courier comes into existence.
    #
    # The outer domain above is derived from the class hierarchy; selecting this
    # one by string prefix was the inconsistency, and the instrument caught it by
    # going red on correct code. The namespace base class IS the gate, so ask it.
    partner_routes = GUARDED_API_ROUTES.select { |r|
      klass = "#{r[:controller]}_controller".camelize.safe_constantize
      klass < Api::V1::Couriers::BaseController || klass < Api::V1::Merchants::BaseController
    }

    it "has partner routes to check" do
      expect(partner_routes).not_to be_empty
    end

    partner_routes.each do |route|
      it "refuses #{route[:verb]} #{route[:spec]}" do
        public_send(route[:verb].downcase, route[:path], headers: auth)

        expect(response).to have_http_status(:forbidden),
                            "#{route[:controller]}##{route[:action]} answered #{response.status} to a signed-in " \
                            "customer who holds no partner role. Holding a session is not holding a role."
        expect(json["code"]).to be_present,
                                "refused without a machine-readable code — the app cannot route this caller " \
                                "to the application path (IDENTITY_AND_ROLES.md §5)"
      end
    end
  end
end
