require "rails_helper"

# "I HAVE A RESTAURANT." The shop's front door, which in v0 is a lead form:
# merchants are not self-serve, Hamma9900 signs them in person, so the app's
# job is to capture the lead and say he will call.
#
# The row it writes is a `merchants` row in its `lead` state — the same row he
# will finish filling in when he calls, which is why there is no leads table
# and no second console surface.
RSpec.describe "Api::V1::MerchantApplications", type: :request do
  def json
    JSON.parse(response.body)
  end

  let(:applicant) { create(:user, phone: "+93700000777", name: "حاجی نعیم") }
  let(:token) { UserSession.issue!(applicant).last }
  let(:auth) { { "Authorization" => "Bearer #{token}" } }
  let(:kind) { create(:merchant_kind, slug: "restaurant", name_en: "Restaurant") }

  def apply(params = {})
    post "/api/v1/merchant_application",
         params: { merchant_application: { name: "کباب هاوس", merchant_kind_id: kind.id }.merge(params) },
         headers: auth
  end

  describe "GET /api/v1/merchant_application" do
    # Not an error — almost nobody has applied. A 404 would have the app render
    # a failure where the correct screen is the empty form.
    it "returns nothing, rather than a 404, when they have not applied" do
      get "/api/v1/merchant_application", headers: auth

      expect(response).to have_http_status(:ok)
      expect(json["merchant_application"]).to be_nil
    end

    it "returns their own application" do
      apply
      get "/api/v1/merchant_application", headers: auth

      expect(json.dig("merchant_application", "name")).to eq("کباب هاوس")
      expect(json.dig("merchant_application", "waiting_for_a_call")).to be true
    end

    # The nil is correct — somebody with no application has none. But a nil is
    # also what a broken endpoint returns to everyone, so the application is
    # shown reaching its own applicant first, in this same example.
    it "does not return somebody else's" do
      apply
      other = create(:user, phone: "+93700000888")

      get "/api/v1/merchant_application", headers: auth
      expect(json["merchant_application"]).to be_present,
                                             "the applicant cannot see his own — the nil below would prove nothing"

      get "/api/v1/merchant_application",
          headers: { "Authorization" => "Bearer #{UserSession.issue!(other).last}" }

      expect(json["merchant_application"]).to be_nil
    end

    it "refuses without a token" do
      get "/api/v1/merchant_application"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/merchant_application" do
    it "records the shop as a lead on the merchants table" do
      expect { apply }.to change(Merchant, :count).by(1)

      lead = Merchant.last
      expect(response).to have_http_status(:created)
      expect(lead).to have_attributes(name: "کباب هاوس", status: "lead", is_open: false)
    end

    # THE IDENTITY LINK, and the only way Hamma9900 finds their account when he
    # calls. Taken from the session, never from the request.
    it "stamps the applicant's own phone as the owner phone" do
      apply(phone: "+93700000999")

      expect(Merchant.last).to have_attributes(
        owner_phone: applicant.phone, owner_name: "حاجی نعیم", phone: "+93700000999"
      )
    end

    it "uses their own number for the shop when they give none" do
      apply

      expect(Merchant.last.phone).to eq(applicant.phone)
    end

    it "keeps the landmark, because that is how anyone will find the place" do
      apply(landmark_note: "شین دروازه، نزدیک پارک")

      expect(Merchant.last.landmark_note).to eq("شین دروازه، نزدیک پارک")
    end

    # ── THE THINGS A LEAD MUST NOT BE ──────────────────────────────────────
    #
    # Assigning an owner GRANTS the merchant role and the board is resolved
    # from `owner_id` alone, so setting it here would hand a merchant board to
    # anyone who typed a shop name into a form.
    it "does not make them the owner, and grants no role" do
      apply

      expect(Merchant.last.owner_id).to be_nil
      expect(applicant.reload.role?(:merchant_owner)).to be false
    end

    it "cannot reach the merchant order board afterwards" do
      apply

      get "/api/v1/merchant/orders", headers: auth

      expect(response).to have_http_status(:forbidden)
      # No merchant at all, because nothing linked them to the row.
      expect(json["code"]).to eq("no_merchant")
    end

    # THE SECOND LAYER, and it is not hypothetical: Hamma9900 may well assign
    # an owner while he is on the phone to a shop that is still a lead. That
    # must not hand over the order board of a shop whose terms nobody has
    # agreed — while `pending` deliberately does pass, because a merchant being
    # onboarded builds their menu before they go live.
    it "still refuses the board if an owner is assigned while it is a lead" do
      apply
      Merchant.last.update!(owner: applicant)

      get "/api/v1/merchant/orders", headers: auth

      expect(response).to have_http_status(:forbidden)
      expect(json["code"]).to eq("merchant_is_a_lead")
    end

    it "opens the board once that same shop is being onboarded" do
      apply
      Merchant.last.update!(owner: applicant, status: :pending)

      get "/api/v1/merchant/orders", headers: auth

      expect(response).to have_http_status(:ok)
    end

    # A lead is not a shop customers can see. `MerchantPolicy::Scope` is
    # `kept.status_active`, and this proves it covers the new state.
    it "is invisible to customers browsing" do
      apply

      get "/api/v1/public/merchants"

      # The subject must EXIST for its absence to mean anything — a lead that was
      # never created is excluded from every list trivially.
      expect(Merchant.unscoped.find_by(name: "کباب هاوس")).to be_present
      expect(json["merchants"].map { |m| m["name"] }).not_to include("کباب هاوس")
    end

    it "is not orderable, whatever else happens" do
      apply

      expect(Merchant.orderable).to be_empty
      expect(Merchant.listed).to be_empty
      expect(Merchant.leads.count).to eq(1)
    end

    # Money and terms are agreed with a human. A form that could set its own
    # commission rate would be the most expensive input field in the app.
    it "ignores anything it was not asked" do
      post "/api/v1/merchant_application",
           params: { merchant_application: {
             name: "Cheeky", merchant_kind_id: kind.id,
             commission_rate: 0, status: "active", owner_id: applicant.id, is_open: true
           } },
           headers: auth

      lead = Merchant.last
      expect(lead.status).to eq("lead")
      expect(lead.commission_rate).to eq(Merchant.new.commission_rate)
      expect(lead.owner_id).to be_nil
      expect(lead.is_open).to be false
    end

    # A retry on a bad connection must not put the same shop on the call list
    # twice — and on an Afghan connection a retry is the normal case.
    it "updates the open lead instead of adding a second row" do
      apply
      expect { apply(name: "کباب هاوس ۲") }.not_to change(Merchant, :count)

      expect(Merchant.last.name).to eq("کباب هاوس ۲")
      expect(response).to have_http_status(:ok)
    end

    # ONE PERSON CAN OWN TWO SHOPS. Once somebody has been called, the row is
    # no longer a lead, so a further submission is a second shop.
    it "starts a new application once the first one has been picked up" do
      apply
      Merchant.last.update!(status: :pending)

      expect { apply(name: "Second Shop") }.to change(Merchant, :count).by(1)
    end

    it "refuses a shop with no name" do
      apply(name: "")

      expect(response).to have_http_status(:unprocessable_content)
      expect(Merchant.count).to eq(0)
    end

    it "refuses a kind that does not exist, rather than guessing one" do
      apply(merchant_kind_id: 0)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "refuses without a token" do
      post "/api/v1/merchant_application", params: { merchant_application: { name: "X" } }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  # WHAT HAPPENS NEXT, end to end: he calls them, finishes the row in the
  # console, assigns the owner — and that last step is what grants the role.
  describe "the whole path from a form to a working merchant account" do
    it "turns a lead into a merchant account when admin assigns the owner" do
      apply
      lead = Merchant.last

      lead.update!(status: :active, owner: applicant, latitude: 34.55, longitude: 69.20)

      expect(applicant.reload.role?(:merchant_owner)).to be true
      session, partner_token = UserSession.issue!(applicant.reload, requested_role: "merchant_owner")
      get "/api/v1/merchant/orders", headers: { "Authorization" => "Bearer #{partner_token}" }

      expect(session.active_role).to eq("merchant_owner")
      expect(response).to have_http_status(:ok)
    end
  end
end
