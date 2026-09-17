require "rails_helper"

# WHAT KIND OF PLACE, for the shop application form.
#
# Public because the person filling that form holds no merchant role — that is
# what they are applying for. Nothing here is sensitive: it is the same
# taxonomy anybody sees by browsing.
RSpec.describe "Api::V1::Public::MerchantKinds", type: :request do
  def json
    JSON.parse(response.body)
  end

  before do
    create(:merchant_kind, slug: "restaurant", name_en: "Restaurant", name_fa: "رستوران",
                           name_ps: "رستوران", position: 0)
    create(:merchant_kind, slug: "bakery", name_en: "Bakery", name_fa: "نانوایی",
                           name_ps: "نانوايي", position: 1)
    create(:merchant_kind, slug: "retired", name_en: "Retired", name_fa: "x", name_ps: "y",
                           position: 2, is_active: false)
  end

  it "is reachable without a token, because an applicant holds no role yet" do
    get "/api/v1/public/merchant_kinds"

    expect(response).to have_http_status(:ok)
    expect(json["merchant_kinds"].map { |k| k["slug"] }).to eq(%w[restaurant bakery])
  end

  it "names them in the caller's language, because a device cannot translate a taxonomy" do
    get "/api/v1/public/merchant_kinds", params: { locale: "ps" }

    expect(json["merchant_kinds"].first["name"]).to eq("رستوران")
  end

  it "defaults to Dari, the most widely spoken in Kabul" do
    get "/api/v1/public/merchant_kinds"

    expect(json["merchant_kinds"].second["name"]).to eq("نانوایی")
  end

  # A retired kind must not be offered to a new applicant, or a shop signs up
  # as something we no longer carry.
  it "omits a kind that has been switched off" do
    get "/api/v1/public/merchant_kinds"

    # by-design: the `before` block creates a retired kind, and the first
    # example asserts the list equals [restaurant, bakery] — the positive is
    # demonstrated, so this absence is real.
    expect(json["merchant_kinds"].map { |k| k["slug"] }).not_to include("retired")
  end

  it "returns them whole, in order, rather than paginated" do
    get "/api/v1/public/merchant_kinds"

    expect(json).not_to have_key("meta")
    expect(json["merchant_kinds"].map { |k| k["id"] }).to eq(MerchantKind.active.ordered.map(&:id))
  end

  # The applicant's own language wins over a query param once they are signed
  # in: the account knows better than the caller.
  it "prefers the signed-in user's own locale" do
    user = create(:user, :customer, locale: "en")
    token = UserSession.issue!(user).last

    get "/api/v1/public/merchant_kinds", params: { locale: "ps" },
                                         headers: { "Authorization" => "Bearer #{token}" }

    expect(json["merchant_kinds"].first["name"]).to eq("Restaurant")
  end
end
