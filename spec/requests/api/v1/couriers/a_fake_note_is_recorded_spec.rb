require "rails_helper"

# ═══ A COUNTERFEIT NOTE AT THE DOOR IS A REASON, AND IT IS COUNTED ═════════
#
# `TRUST_AND_REPUTATION.md` §4, decided: *"the courier checks notes at the
# point of collection, and a fake note he accepts is his loss... A `fake_note`
# reason code on the customer (§2) is how a pattern gets spotted; a customer
# who passes two is not making mistakes."* §2 lists it among the reports that
# accumulate against the customer. It existed nowhere.
#
# THE API HALF. `problem_reasons` is a list of bare keys the courier app labels
# itself, so a new key would reach every courier as the raw string `fake_note`
# until the app ships its words. So the reason is recorded and counted now, and
# OFFERED to the app only once `fake_note_reason_offered` is on — the switch the
# mobile side flips with its labels. The console offers it always.
RSpec.describe "a fake note is recorded", type: :request do
  let(:courier) { create(:user, :courier) }
  let(:customer) { create(:user, :customer) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(courier).last}" } }
  let!(:order) { create(:order, :with_items, :picked_up, customer: customer, courier: courier) }

  def offer_fake_note!
    Setting.find_or_initialize_by(key: "fake_note_reason_offered").update!(value: "true", value_type: :boolean)
  end

  def report(reason)
    post "/api/v1/courier/jobs/delivery/#{order.id}/problem", params: { reason: reason }, headers: auth
  end

  context "before the app can label it" do
    it "is not offered on the courier's problem sheet" do
      get "/api/v1/courier/job", headers: auth

      reasons = JSON.parse(response.body).dig("job", "problem_reasons")
      expect(reasons).to include("nobody_home")
      expect(reasons).not_to include("fake_note")
    end

    it "is refused from the app, as any reason the sheet did not offer" do
      report("fake_note")

      expect(response).to have_http_status(:unprocessable_content)
      expect(order.reload.status).to eq("picked_up")
    end

    it "can still be recorded by an operator told on the phone" do
      admin = AdminUser.create!(name: "Ops", email: "ops@karwan.af", password: "a-long-test-password")
      post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }

      patch "/admin/orders/#{order.id}/fail", params: { reason: "fake_note" }

      expect(order.reload.failure_reason).to eq("fake_note")
    end
  end

  context "once the app can" do
    before { offer_fake_note! }

    it "is offered, accepted, and fails the job with the reason" do
      get "/api/v1/courier/job", headers: auth
      expect(JSON.parse(response.body).dig("job", "problem_reasons")).to include("fake_note")

      report("fake_note")

      expect(response).to have_http_status(:ok)
      expect(order.reload).to have_attributes(status: "failed", failure_reason: "fake_note")
    end

    # §4: "a customer who passes two is not making mistakes" — the count is
    # the whole point, and it lands on the same line as the other reports.
    it "accumulates against the customer" do
      report("fake_note")

      expect(customer.reload.delivery_failures_summary).to start_with("fake note ×1")
    end

    it "is a reason on a ride too, where the fare is cash at the end" do
      expect(Trip.offered_failure_reasons).to include("fake_note")
    end
  end
end
