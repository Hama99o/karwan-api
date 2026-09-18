require "rails_helper"

# ═══ A THEME IS A PREFERENCE OF A PERSON ═══════════════════════════════════
#
# Hamma9900 asked for it by name — "like same thing language and theme, it's
# important" — and the same sentence is the design: **theme behaves like
# locale.** AFGHAN_UX.md §7 is why that matters here rather than being a tidy
# analogy: **phones are shared.** A father and a son on one handset are two
# people with two languages and two eyes, and a preference stored on the device
# gives the second one the first one's choice.
#
# The mobile store had REMOVED its own `updateMe({ preferredTheme })` call
# rather than stub it — "There is no API yet, and when there is, the theme
# belongs on the user for the same reason the language does" — and held the gap
# open with an example that fails the day the field lands. That is the deferral
# pattern applied to a field, and it is why this arrived as a request rather
# than a surprise.
RSpec.describe "Api::V1::Me preferred_theme", type: :request do
  def json
    JSON.parse(response.body)
  end

  let(:user) { create(:user, :customer) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(user).last}" } }

  it "defaults to system, which is the honest answer" do
    get "/api/v1/me", headers: auth

    # The OS already knows whether the phone is in Kabul sunlight or a dark
    # room, and guessing worse than the OS is not a feature.
    expect(json.dig("user", "preferred_theme")).to eq("system")
  end

  it "is saved on the person and comes back on the next request" do
    patch "/api/v1/me", params: { preferred_theme: "dark" }, headers: auth

    expect(response).to have_http_status(:ok)
    expect(json.dig("user", "preferred_theme")).to eq("dark")
    expect(user.reload.preferred_theme).to eq("dark")
  end

  # ── THE WHOLE POINT, AND THE REASON IT IS NOT ON THE DEVICE ──────────────
  #
  # Two people, one handset. Stored per device, the second person inherits the
  # first one's choice — which is the same failure `locale` would have had.
  it "follows the person rather than the handset" do
    other = create(:user, :customer)
    other_auth = { "Authorization" => "Bearer #{UserSession.issue!(other).last}" }

    patch "/api/v1/me", params: { preferred_theme: "dark" }, headers: auth
    get "/api/v1/me", headers: other_auth

    expect(json.dig("user", "preferred_theme")).to eq("system"),
                                                   "a second person on the same phone inherited the first one's theme"
  end

  it "accepts each of the three the app offers" do
    User::THEMES.each do |theme|
      patch "/api/v1/me", params: { preferred_theme: theme }, headers: auth

      expect(response).to have_http_status(:ok), "#{theme} was refused"
      expect(user.reload.preferred_theme).to eq(theme)
    end
  end

  it "refuses a theme the app cannot render" do
    patch "/api/v1/me", params: { preferred_theme: "sepia" }, headers: auth

    expect(response).to have_http_status(:unprocessable_content)
    expect(user.reload.preferred_theme).to eq("system")
  end

  # It travels beside `locale` because they are the same kind of fact about the
  # same person, and a client reading one should not look elsewhere for the
  # other.
  it "is served beside the language, not somewhere else" do
    get "/api/v1/me", headers: auth

    expect(json["user"]).to include("locale", "preferred_theme")
  end
end
