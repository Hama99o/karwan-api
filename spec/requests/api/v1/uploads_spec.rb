require "rails_helper"

# THE FILES THIS PLATFORM IS BUILT ON, and could not accept.
#
# Eight `has_one_attached` macros were declared across this schema and NO
# endpoint or admin field ever accepted one. Every gate stayed green because
# the macro does not touch the database — the same shape docs/NOTES.md records
# for Active Storage never having been installed at all.
#
# Two of the eight are not conveniences:
#   • a catalog item's PHOTO — AFGHAN_UX.md §1 puts photos first, and that is a
#     literacy argument before an aesthetic one: a customer who reads Pashto
#     slowly still recognises kabab. Without it every dish is a name and a price.
#   • an address's VOICE NOTE — §2 makes it the answer to low literacy, and
#     CLAUDE.md's address problem says the same from the other side: a pin, a
#     spoken landmark and a phone number, never a typed street address.
RSpec.describe "uploads", type: :request do
  def json = JSON.parse(response.body)

  let(:photo) { fixture_file_upload("photo.png", "image/png") }
  let(:voice) { fixture_file_upload("voice_note.m4a", "audio/mp4") }

  describe "a merchant's dish photo" do
    let(:owner) { create(:user, :merchant_owner) }
    let(:merchant) { create(:merchant, owner: owner) }
    let(:category) { create(:catalog_category, merchant: merchant) }
    let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(owner).last}" } }

    it "is accepted on create and served back to customers" do
      post "/api/v1/merchant/catalog_items",
           params: { catalog_item: { catalog_category_id: category.id, name: "چکن کباب", price: 400 },
                     photo: photo },
           headers: auth

      expect(response).to have_http_status(:created)
      item = CatalogItem.find(json.dig("catalog_item", "id"))
      expect(item.photo).to be_attached

      # The whole point: it reaches the customer's menu.
      get "/api/v1/public/merchants/#{merchant.id}/catalog"
      photo_url = json["catalogs"].first["items"].first["photo_url"]
      expect(photo_url).to be_present
    end

    it "is accepted on update without disturbing the price" do
      item = create(:catalog_item, catalog_category: category, merchant: merchant, price: 400)

      patch "/api/v1/merchant/catalog_items/#{item.id}",
            params: { catalog_item: { name: item.name }, photo: photo }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(item.reload.photo).to be_attached
      expect(item.price).to eq(400)
    end

    # An edit that changes a price must not silently delete the photograph the
    # merchant uploaded last week.
    it "leaves an existing photo alone when none is sent" do
      item = create(:catalog_item, catalog_category: category, merchant: merchant)
      item.photo.attach(io: File.open(file_fixture("photo.png")), filename: "p.png", content_type: "image/png")

      patch "/api/v1/merchant/catalog_items/#{item.id}",
            params: { catalog_item: { price: 450 } }, headers: auth

      expect(item.reload.photo).to be_attached
      expect(item.price).to eq(450)
    end

    # This image is downloaded by every customer who opens the menu, on a
    # connection where data costs them real money.
    it "refuses a file that is not an image" do
      post "/api/v1/merchant/catalog_items",
           params: { catalog_item: { catalog_category_id: category.id, name: "x", price: 1 },
                     photo: voice },
           headers: auth

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "refuses another merchant's catalog" do
      merchant # this owner must HAVE a merchant, or the refusal is `no_merchant`
      other = create(:catalog_category)

      post "/api/v1/merchant/catalog_items",
           params: { catalog_item: { catalog_category_id: other.id, name: "x", price: 1 }, photo: photo },
           headers: auth

      # 404, not 403: the category simply is not in this merchant's scope, and
      # saying "forbidden" would confirm that somebody else's category exists.
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "a customer's landmark voice note" do
    let(:customer) { create(:user, :customer) }
    let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(customer).last}" } }
    let(:pin) { { address: { latitude: 34.54, longitude: 69.17, label: "کور" } } }

    it "is accepted, and the flag is DERIVED from the file rather than claimed" do
      post "/api/v1/customer/addresses", params: pin.merge(voice_note: voice), headers: auth

      expect(response).to have_http_status(:created)
      expect(json.dig("address", "has_voice_note")).to be true
      expect(json.dig("address", "voice_note_url")).to be_present
      expect(Address.find(json.dig("address", "id")).voice_note).to be_attached
    end

    # The bug this closes: `has_voice_note` was a boolean the client could set
    # while no endpoint accepted a file, so it could only ever be a claim about
    # a recording that did not exist — and a courier would arrive at a door
    # expecting a note the app cannot play.
    it "never claims a voice note that was not uploaded" do
      post "/api/v1/customer/addresses",
           params: { address: pin[:address].merge(has_voice_note: true, voice_note_seconds: 12) },
           headers: auth

      expect(json.dig("address", "has_voice_note")).to be false
      expect(json.dig("address", "voice_note_url")).to be_nil
    end

    # A pin plus a spoken landmark is a findable address; a bare pin often is
    # not, in a city navigated by landmark.
    it "makes a bare pin navigable" do
      post "/api/v1/customer/addresses", params: pin, headers: auth
      expect(json.dig("address", "navigable")).to be false

      address = Address.find(json.dig("address", "id"))
      patch "/api/v1/customer/addresses/#{address.id}",
            params: { voice_note: voice }, headers: auth

      expect(json.dig("address", "navigable")).to be true
    end

    it "refuses an image where a recording belongs" do
      post "/api/v1/customer/addresses", params: pin.merge(voice_note: photo), headers: auth

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "refuses without a token" do
      post "/api/v1/customer/addresses", params: pin.merge(voice_note: voice)

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
