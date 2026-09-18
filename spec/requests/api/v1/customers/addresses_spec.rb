require "rails_helper"

RSpec.describe "Api::V1::Customers::Addresses", type: :request do
  def json
    JSON.parse(response.body)
  end

  let(:customer) { create(:user, :customer) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(customer).last}" } }

  # AN ADDRESS IS A PIN, A VOICE NOTE AND A PHONE NUMBER. Afghan addresses are
  # unreliable and people navigate by landmarks, so there is deliberately no
  # street, city or postcode anywhere in this payload.
  let(:pin) do
    {
      address: {
        label: "خانه",
        latitude: 34.5400, longitude: 69.1750,
        landmark_note: "دروازه آبی نزدیک پارک شهر نو، طبقه دوم",
        phone: "+93700000123"
      }
    }
  end

  describe "POST /api/v1/customer/addresses" do
    it "saves a pin with a landmark and a phone" do
      post "/api/v1/customer/addresses", params: pin, headers: auth

      expect(response).to have_http_status(:created)
      expect(json.dig("address", "label")).to eq("خانه")
      expect(json.dig("address", "location", "latitude").to_f).to eq(34.54)
      expect(json.dig("address", "navigable")).to be true
    end

    it "takes no street, city or postcode, because there is no such thing here" do
      post "/api/v1/customer/addresses",
           params: { address: pin[:address].merge(street: "Main St", city: "Kabul") }, headers: auth

      expect(response).to have_http_status(:created)
      # by-design: a created address always has keys, and the status is asserted above.
      expect(json["address"].keys).not_to include("street", "city")
    end

    it "refuses a pin that is not on Earth" do
      post "/api/v1/customer/addresses",
           params: { address: pin[:address].merge(latitude: 91) }, headers: auth

      expect(response).to have_http_status(:unprocessable_content)
    end

    # ── AN ERROR AN AFGHAN USER CANNOT READ IS NOT AN ERROR MESSAGE ──────────
    #
    # `errors` is English prose with no field and no code, so a screen could
    # neither translate it nor put it under the input that caused it — for
    # somebody AFGHAN_UX.md §1 says may not read fluently. `field_errors` is the
    # same failure as { field => [code] }, which the app localises with its own
    # i18n, the way it does every other error in this API.
    it "names the field and the reason as CODES, not as an English sentence" do
      post "/api/v1/customer/addresses",
           params: { address: pin[:address].merge(latitude: 91) }, headers: auth

      expect(json["field_errors"]).to be_present
      expect(json["field_errors"].keys).to include("latitude")
      expect(json["field_errors"]["latitude"]).to be_an(Array)
      # A code, not prose: no spaces and no apostrophes.
      expect(json["field_errors"]["latitude"]).to all(match(/\A[a-z_]+\z/))
    end

    it "keeps `errors` exactly as it was, because the console and two specs read it" do
      post "/api/v1/customer/addresses",
           params: { address: pin[:address].merge(latitude: 91) }, headers: auth

      expect(json["errors"]).to be_an(Array)
      expect(json["errors"].join).to match(/[A-Z]/)
    end

    # A bare pin is often not enough in a city navigated by landmark, so the
    # payload says whether a courier could actually find it.
    it "flags a bare pin as not navigable" do
      post "/api/v1/customer/addresses",
           params: { address: { latitude: 34.54, longitude: 69.175 } }, headers: auth

      expect(json.dig("address", "navigable")).to be false
    end

    it "refuses without a token" do
      post "/api/v1/customer/addresses", params: pin

      expect(response).to have_http_status(:unauthorized)
      expect(Address.count).to eq(0)
    end
  end

  describe "GET /api/v1/customer/addresses" do
    it "returns the person's own pins, default first" do
      create(:address, user: customer, label: "Work")
      create(:address, :default, user: customer, label: "Home")

      get "/api/v1/customer/addresses", headers: auth

      expect(json["addresses"].map { |a| a["label"] }).to eq([ "Home", "Work" ])
    end

    # A saved address is where somebody lives.
    # `be_empty` catches a leak but passes just as happily on an endpoint that
    # returns nothing to anybody. His own pin makes the difference observable.
    it "never returns another customer's pins" do
      mine = create(:address, user: customer, label: "خانه")
      theirs = create(:address, user: create(:user, :customer), label: "Someone Else")

      get "/api/v1/customer/addresses", headers: auth

      ids = json["addresses"].map { |a| a["id"] }
      expect(ids).to include(mine.id), "his own pins are missing — the exclusion below would be weak"
      expect(ids).not_to include(theirs.id)
    end

    it "excludes a discarded pin" do
      create(:address, :discarded, user: customer, label: "Old place")

      get "/api/v1/customer/addresses", headers: auth

      expect(json["addresses"]).to be_empty
    end
  end

  describe "PATCH and DELETE" do
    let!(:address) { create(:address, user: customer) }

    it "updates a landmark note" do
      patch "/api/v1/customer/addresses/#{address.id}",
            params: { address: { landmark_note: "سبز دروازه" } }, headers: auth

      expect(address.reload.landmark_note).to eq("سبز دروازه")
    end

    it "refuses to update someone else's pin" do
      other = create(:address, user: create(:user, :customer))

      patch "/api/v1/customer/addresses/#{other.id}",
            params: { address: { label: "Mine now" } }, headers: auth

      expect(response).to have_http_status(:not_found)
    end

    # One-way door #6: soft delete.
    it "discards rather than destroying" do
      delete "/api/v1/customer/addresses/#{address.id}", headers: auth

      expect(response).to have_http_status(:no_content)
      expect(address.reload).to be_discarded
    end

    # ORDERS SNAPSHOT THE ADDRESS. Deleting a pin must never rewrite where a
    # past order actually went.
    it "leaves a past order's delivery address untouched" do
      order = create(:order, customer: customer,
                             delivery_landmark_note: "دروازه آبی", delivery_latitude: 34.54,
                             delivery_longitude: 69.175)

      delete "/api/v1/customer/addresses/#{address.id}", headers: auth

      expect(order.reload.delivery_landmark_note).to eq("دروازه آبی")
      expect(order.delivery_latitude).to eq(BigDecimal("34.54"))
    end
  end

  describe "POST /api/v1/customer/addresses/:id/make_default" do
    it "moves the default, leaving exactly one" do
      first = create(:address, :default, user: customer)
      second = create(:address, user: customer)

      post "/api/v1/customer/addresses/#{second.id}/make_default", headers: auth

      expect(second.reload.is_default).to be true
      expect(first.reload.is_default).to be false
      expect(customer.addresses.where(is_default: true).count).to eq(1)
    end
  end
end
