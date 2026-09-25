require "rails_helper"

# WHERE AN ERROR GOES (launch readiness A6, 25 Sept 2026).
#
# Rails reports every unhandled request error to `Rails.error`; nothing
# subscribed, so a checkout 500 lived only in a container log until the next
# deploy. Now it is logged (always) and kept on the console (when it can be),
# redacted at capture, counted per distinct error, and pruned.
RSpec.describe "Every error is seen", type: :request do
  let(:customer) { create(:user, :customer) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(customer).last}" } }
  let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075) }
  let!(:kabab) { create(:catalog_item, catalog_category: create(:catalog_category, merchant: merchant), price: 400) }

  # A message stuffed with what a real one can carry: a phone, an email, a
  # landmark in quotes, coordinates, and a Postgres DETAIL quoting the row.
  SENSITIVE = "PG::UniqueViolation: Key (phone)=(+93700111222) already exists near " \
              "'blue gate by Shar-e-Naw park' for ahmad@example.com at 34.55531,69.20751 " \
              "call 0700 111 222\nDETAIL: Failing row contains (7, +93700111222, blue gate)".freeze

  def quote!
    post "/api/v1/customer/orders/quote",
         params: { order: { merchant_id: merchant.id, delivery_latitude: 34.5401, delivery_longitude: 69.1751,
                            lines: [ { catalog_item_id: kabab.id, quantity: 1 } ] } },
         headers: auth
  end

  def blow_up!(message = SENSITIVE)
    allow(Pricing::Quote).to receive(:new).and_raise(RuntimeError, message)
    expect { quote! }.to raise_error(RuntimeError)
  end

  it "keeps a checkout error, from the real request path" do
    expect { blow_up! }.to change(ErrorReport, :count).by(1)

    report = ErrorReport.last
    expect(report.error_class).to eq("RuntimeError")
    expect(report.source).to eq("application.action_dispatch")
    expect(report.handled).to be false
  end

  it "keeps no phone, email, landmark, coordinate or quoted row" do
    blow_up!
    kept = ErrorReport.last.attributes.values.join(" ")

    %w[700111222 0700 111 ahmad@example.com blue\ gate Shar-e-Naw 34.55531 69.20751].each do |leak|
      expect(kept).not_to include(leak), "#{leak.inspect} reached error_reports"
    end
    expect(ErrorReport.last.message).to include("PG::UniqueViolation", "already exists")
  end

  it "counts the same error once, however often it happens" do
    3.times { blow_up! }

    expect(ErrorReport.count).to eq(1)
    expect(ErrorReport.last.occurrences).to eq(3)
  end

  it "keeps a different error separately" do
    blow_up!
    allow(Pricing::Quote).to receive(:new).and_raise(ArgumentError, "something else")
    expect { quote! }.to raise_error(ArgumentError)

    expect(ErrorReport.pluck(:error_class)).to contain_exactly("RuntimeError", "ArgumentError")
  end

  # THE OUTAGE CASE: the database is what failed, so the row can't be written.
  # The log line must still appear, and the reporter must not raise a second
  # error into the request.
  it "still logs the error when it cannot be kept" do
    allow(ErrorReport).to receive(:record!).and_raise(ActiveRecord::ConnectionNotEstablished)
    lines = []
    allow(Rails.logger).to receive(:error).and_wrap_original { |m, msg| lines << msg; m.call(msg) }

    blow_up!

    expect(lines.grep(/\A\[error-report\] RuntimeError /).size).to eq(1)
    expect(lines.grep(/could not be kept/).size).to eq(1)
    expect(lines.join).not_to include("700111222")
  end

  it "shows it on the console" do
    blow_up!
    admin = AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password")
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }

    get "/admin/error_reports"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("RuntimeError")

    get "/admin/error_reports/#{ErrorReport.last.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("700111222")
  end

  describe "retention" do
    def report!(fingerprint, last_seen)
      ErrorReport.create!(fingerprint: fingerprint, error_class: "E", severity: "error",
                          first_seen_at: last_seen, last_seen_at: last_seen)
    end

    it "forgets what was last seen more than 30 days ago" do
      report!("old", 31.days.ago)
      report!("recent", 2.days.ago)

      PruneErrorReportsJob.perform_now

      expect(ErrorReport.pluck(:fingerprint)).to eq([ "recent" ])
    end

    it "keeps at most the newest 500 distinct errors" do
      stub_const("ErrorReport::KEEP_AT_MOST", 2)
      report!("a", 3.hours.ago)
      report!("b", 2.hours.ago)
      report!("c", 1.hour.ago)

      PruneErrorReportsJob.perform_now

      expect(ErrorReport.pluck(:fingerprint)).to contain_exactly("b", "c")
    end

    it "runs every day, not when somebody remembers" do
      recurring = YAML.safe_load(Rails.root.join("config/recurring.yml").read, aliases: true)
      expect(recurring.dig("production", "prune_error_reports", "class")).to eq("PruneErrorReportsJob")
    end
  end
end
