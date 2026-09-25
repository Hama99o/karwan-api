require "rails_helper"

# A POLL'S COST IS MOSTLY HEADERS (lib/middleware/api_header_diet.rb). Driven
# through the whole stack, because what matters is what a response CARRIES,
# not what a list of middleware says it should.
RSpec.describe ApiHeaderDiet, type: :request do
  let(:courier) { create(:user, :courier) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(courier).last}" } }

  it "sends a phone none of the browser-only or debugging headers" do
    get "/api/v1/courier/offer", headers: auth

    expect(response).to have_http_status(:ok)
    expect(response.headers.to_h.keys.map(&:downcase) & ApiHeaderDiet::DROPPED).to eq([])
  end

  it "keeps what the client or a browser opening the URL depends on" do
    get "/api/v1/courier/offer", headers: auth

    expect(response.headers["x-content-type-options"]).to eq("nosniff")
    expect(response.headers["etag"]).to be_present
    expect(response.headers["cache-control"]).to be_present
    expect(response.headers["content-type"]).to start_with("application/json")
  end

  it "still answers a 304 without them" do
    get "/api/v1/courier/offer", headers: auth
    get "/api/v1/courier/offer", headers: auth.merge("If-None-Match" => response.headers["etag"])

    expect(response).to have_http_status(:not_modified)
    expect(response.headers.to_h.keys.map(&:downcase) & ApiHeaderDiet::DROPPED).to eq([])
  end

  # A money console in a frame is a clickjacking target.
  it "leaves the console's browser protections alone" do
    get "/admin/login"

    expect(response.headers["x-frame-options"]).to eq("SAMEORIGIN")
    expect(response.headers["referrer-policy"]).to be_present
  end
end
