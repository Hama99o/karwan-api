require "rails_helper"

# ═══ §5-A AND §5-E ON THE REPORT — THE COURIER'S SIDE OF "SHOPS TO RING" ═══
#
# §5-E says *"unusually high... for one driver"*, which only means something
# against the others. So the reading that matters is the RANKING, beside the
# shop one, and it is asserted here as values read by column name — never a
# label, never a negative on its own (`docs/NOTES.md`: an absent name proves
# nothing when the likeliest reason is that nothing rendered).
#
# ── THE DISCRIMINATING INPUTS ─────────────────────────────────────────────
#
# - `busy`: 10 answered, 5 not taken → listed, at 50.0% with its denominator.
# - `new_one`: 4 answered, all declined → under the floor, NOT listed.
# - `perfect`: 10 answered, all taken → nothing to ring about, NOT listed.
# - `pair`: one offer, but the same passenger in two rides ended mid-way →
#   listed whatever his volume, and FIRST.
RSpec.describe "which courier to ring", type: :request do
  let(:admin) { AdminUser.create!(name: "Ops", email: "ring@karwan.af", password: "a-long-test-password") }

  let(:busy) { create(:user, :ride_courier, name: "Busy Rider") }
  let(:new_one) { create(:user, :ride_courier, name: "New Rider") }
  let(:perfect) { create(:user, :ride_courier, name: "Perfect Rider") }
  let(:pair) { create(:user, :ride_courier, name: "Pair Driver") }
  let(:passenger) { create(:user, :customer, name: "Same Passenger") }

  def answers(courier, accepted: 0, declined: 0, timed_out: 0)
    { accepted: accepted, declined: declined, timed_out: timed_out }.each do |status, n|
      n.times { create(:offer, courier: courier, status: status, offered_at: 2.days.ago, expires_at: 2.days.ago + 1.minute) }
    end
  end

  def ended_mid_way(driver, rider)
    create(:trip, :in_progress, courier: driver, passenger: rider)
      .tap { |t| t.update_columns(status: Trip.statuses[:failed], failure_reason: Trip.failure_reasons[:passenger_refused], failed_at: 1.day.ago) }
  end

  def rows
    page = Nokogiri::HTML(response.body)
    table = page.css("h2").detect { |h| h.text.start_with?("Couriers to ring") }
                &.xpath("following-sibling::table[1]")&.first
    return [] if table.nil?

    headers = table.css("thead th").map { |th| th.text.strip }
    table.css("tbody tr").map { |tr| headers.zip(tr.css("td").map { |td| td.text.squish }).to_h }
  end

  before do
    answers(busy, accepted: 5, declined: 3, timed_out: 2)
    answers(new_one, declined: 4)
    answers(perfect, accepted: 10)
    answers(pair, accepted: 1)
    2.times { ended_mid_way(pair, passenger) }

    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
    get "/admin/reports"
    expect(response).to have_http_status(:ok)
  end

  it "lists the courier with the recurring passenger first, then by share not taken" do
    expect(rows.map { |r| r["Courier"] }).to eq([ "Pair Driver", "Busy Rider" ])
  end

  it "gives the share with its denominator, and declined apart from let run out" do
    busy_row = rows.detect { |r| r["Courier"] == "Busy Rider" }

    expect(busy_row).to include("Not taken" => "50.0% (5 of 10 offers)", "Declined" => "3", "Let run out" => "2")
  end

  it "names the passenger who recurs among rides ended mid-way" do
    pair_row = rows.detect { |r| r["Courier"] == "Pair Driver" }

    expect(pair_row).to include("Rides ended mid-way" => "2", "Same passenger again" => "Same Passenger ×2")
  end

  it "costs the same queries however many couriers it ranks" do
    count = lambda do
      n = 0
      sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        n += 1 unless payload[:name].to_s.match?(/SCHEMA|TRANSACTION/)
      end
      Couriers::Reliability.ranked
      n
    ensure
      ActiveSupport::Notifications.unsubscribe(sub)
    end

    few = count.call
    3.times { answers(create(:user, :ride_courier), accepted: 3, declined: 3) }
    expect(count.call).to eq(few)
  end
end
