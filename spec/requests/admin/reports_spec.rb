require "rails_helper"

# The four figures PRODUCT.md asks for that nothing carried:
# orders per day, gross value, commission, rider utilisation, failure reasons.
#
# Every example plants the data and checks the number MOVES. A report that
# renders is not a report that counts, and a page of zeroes looks identical to
# a page whose queries are wrong.
RSpec.describe "Admin reports", type: :request do
  let(:admin) { AdminUser.create!(name: "Ops", email: "reports@karwan.af", password: "a-long-test-password") }

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  # Order validates `customer_total == items_total + delivery_fee`, so the parts
  # are set explicitly rather than only the total. Written the lazy way first
  # and the model refused it — the invariant this report depends on is enforced
  # at the row, which is why the figures can be trusted at all.
  DELIVERY_FEE = 100

  def delivered_order(courier:, at:, commission:, total:)
    create(:order, :with_items, :delivered, courier: courier, commission: commission,
                                            items_total: total - DELIVERY_FEE,
                                            delivery_fee: DELIVERY_FEE,
                                            customer_total: total,
                                            courier_fee: DELIVERY_FEE,
                                            merchant_payout: total - DELIVERY_FEE - commission,
                                            delivered_at: at)
  end

  it "opens" do
    get "/admin/reports"
    expect(response).to have_http_status(:ok)
  end

  it "separates what customers paid from what we earned" do
    courier = create(:user, :courier)
    delivered_order(courier: courier, at: 1.day.ago, commission: 50, total: 500)
    delivered_order(courier: courier, at: 2.days.ago, commission: 70, total: 900)

    get "/admin/reports"

    # 1,400 passed through; 120 is ours. Showing either one alone, or their sum,
    # would misstate the business by an order of magnitude.
    expect(response.body).to include("1,400")
    expect(response.body).to include("120")
  end

  # THE NUMBER THAT DECIDES THE BUSINESS. Two riders, six jobs, so the figure
  # must reflect BOTH terms — a version dividing by the wrong denominator, or
  # not dividing at all, gives a different answer for this data.
  it "reports utilisation with its numerator and denominator on the page" do
    a = create(:user, :courier)
    b = create(:user, :courier)
    3.times { |i| delivered_order(courier: a, at: (i + 1).days.ago, commission: 10, total: 500) }
    3.times { |i| delivered_order(courier: b, at: (i + 1).days.ago, commission: 10, total: 500) }

    get "/admin/reports"

    expect(response.body).to include("6 jobs"), "the numerator is not shown"
    expect(response.body).to include("2 riders"), "the denominator is not shown"
  end

  it "says plainly that the utilisation figure flatters the business" do
    get "/admin/reports"

    expect(response.body).to include("flatters the business"),
                             "a hiring decision will be made on this number; the bias must be on the page"
  end

  it "ranks failure reasons and omits the ones that did not happen" do
    courier = create(:user, :courier)
    2.times { create(:order, :with_items, :failed, courier: courier, failure_reason: :nobody_home) }
    create(:order, :with_items, :failed, courier: courier, failure_reason: :wrong_address)

    get "/admin/reports"

    expect(response.body).to include("Nobody home")
    expect(response.body).to include("Wrong address")
    expect(response.body).not_to include("Customer unreachable"),
                                 "a reason that did not occur is listed, which hides the one that is climbing"
  end

  # ── THE KABUL DAY ──────────────────────────────────────────────────────────
  #
  # Kabul is UTC+4:30, so an order at 21:00Z belongs to the NEXT Kabul day.
  # Grouped by the server's date instead, the whole dinner rush lands on the
  # previous row. This example fails against `DATE(delivered_at)` and passes
  # against `DATE(... AT TIME ZONE 'Asia/Kabul')`.
  it "counts an order by the day it was in Kabul, not the day it was in UTC" do
    courier = create(:user, :courier)
    at = Time.utc(Time.current.year, Time.current.month, Time.current.day, 21, 0, 0) - 2.days
    delivered_order(courier: courier, at: at, commission: 10, total: 500)

    get "/admin/reports"

    kabul_day = at.in_time_zone("Kabul").to_date
    utc_day = at.to_date
    expect(kabul_day).not_to eq(utc_day), "pick an instant where the two dates differ, or this proves nothing"

    # ── ASSERT THE COUNT, NOT THE LABEL ──────────────────────────────────
    #
    # The first version of this example checked that the Kabul date APPEARED in
    # the page, and it passed against the UTC-grouped version too — because the
    # table renders a row for every date in the window, so every label is always
    # present and only the NUMBER moves. It was a vacuous assertion inside the
    # example written to catch a timezone bug.
    expect(delivered_on(kabul_day)).to eq(1),
                                       "the delivery is not counted on its Kabul day"
    expect(delivered_on(utc_day)).to eq(0),
                                     "the delivery is counted on the SERVER's day — 19:30 to midnight in Kabul, " \
                                     "the whole dinner rush, would land on the row before"
  end

  # Pulls the `delivered` cell out of the row for one date, so the assertions
  # above are about the figure rather than about the page containing a string.
  def delivered_on(date)
    label = Regexp.escape(date.strftime("%a %d %b"))
    row = response.body[/<td>#{label}<\/td>\s*<td>\s*(\d+)\s*<\/td>\s*<td>\s*(\d+)\s*<\/td>/m]
    return nil if row.nil?

    Regexp.last_match(2).to_i
  end
end
