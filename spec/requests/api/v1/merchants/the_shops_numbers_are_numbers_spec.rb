require "rails_helper"

# Found live by karwan-42 on 25 Sept 2026: PATCH /merchant/profile took
# `"phone": "not a phone"`, answered 200, and served it back. This is the
# number couriers and customers ring; the contact person's is the one the
# unanswered-order escalation rings. Also: the contact person was served
# but not writable, and `description` was writable but not served.
RSpec.describe "A shop's numbers are numbers", type: :request do
  let(:owner) { create(:user, :merchant_owner) }
  let!(:merchant) { create(:merchant, owner: owner, phone: "+93700000111") }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(owner).last}" } }

  def json = JSON.parse(response.body)
  def save(fields) = patch("/api/v1/merchant/profile", params: { merchant: fields }, headers: auth)

  it "refuses a phone that is not one, and names the field for the form" do
    save(phone: "not a phone")

    expect(response).to have_http_status(:unprocessable_content)
    expect(json["field_errors"]).to eq("phone" => [ "invalid" ])
    expect(merchant.reload.phone).to eq("+93700000111")
  end

  it "stores any spelling of a real number in one form" do
    save(phone: "0700 222 333")

    expect(response).to have_http_status(:ok)
    expect(merchant.reload.phone).to eq("+93700222333")
  end

  it "lets the shop name its own contact person, and checks that number too" do
    save(contact_person_name: "Wahid", contact_person_phone: "0799 111 222")
    expect(response).to have_http_status(:ok)
    expect(merchant.reload).to have_attributes(contact_person_name: "Wahid", contact_person_phone: "+93799111222")

    save(contact_person_phone: "12")
    expect(json["field_errors"]).to eq("contact_person_phone" => [ "invalid" ])
  end

  it "allows no contact phone at all" do
    save(contact_person_phone: "")

    expect(response).to have_http_status(:ok)
  end

  it "serves the description it lets the shop write, so a form can prefill it" do
    save(description: "Kabuli pulao since 1998")

    get "/api/v1/merchant/profile", headers: auth
    expect(json.dig("profile", "description")).to eq("Kabuli pulao since 1998")
  end
end
