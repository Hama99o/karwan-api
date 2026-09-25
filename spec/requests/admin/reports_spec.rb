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

  describe "the honest denominator" do
    # The gap between "per working rider" and "per available rider" IS the idle
    # capacity, and it is the number a hiring decision turns on.
    it "divides by everyone who went on shift, not only those who finished a job" do
      worked = create(:user, :courier)
      idle = create(:user, :courier)
      # BEFORE the 14-day window, deliberately: the report shows this figure
      # only once shift history predates the whole window, because dividing by
      # a partially-recorded denominator reports a crisis rather than the truth.
      [ worked, idle ].each do |c|
        c.courier_shifts.create!(started_at: 20.days.ago, ended_at: 19.days.ago)
        c.courier_shifts.create!(started_at: 3.days.ago, ended_at: 2.days.ago)
      end
      2.times { |i| delivered_order(courier: worked, at: (i + 1).days.ago, commission: 10, total: 500) }

      get "/admin/reports"

      expect(response.body).to include("2 riders who went on shift"),
                               "the idle rider is missing from the denominator, which is the whole point"
    end

    # Recording began the day the table shipped and CANNOT be backfilled, so a
    # window that predates it would divide by a denominator missing most of its
    # subjects — reporting a crisis instead of flattery, which is the same error
    # in the other direction.
    it "refuses to show the figure when history does not cover the window" do
      create(:user, :courier).courier_shifts.create!(started_at: 1.hour.ago)

      get "/admin/reports"

      expect(response.body).to include("Shift history does not cover this whole window")
      expect(response.body).not_to include("jobs per <em>available</em> rider per day")
    end

    it "says so plainly when nothing has been recorded at all" do
      get "/admin/reports"

      expect(response.body).to include("cannot be backfilled")
    end
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

  # ── DEMAND WE COULD NOT SERVE ──────────────────────────────────────────────
  #
  # `cancellation_reason` has been written since the first cancel endpoint and
  # counted nowhere. One of its values is a different kind of number:
  # `no_courier_available` means a passenger asked and we had nobody to send.
  # (The "21 of 25 on the rig" once quoted here was a seed artefact, not
  # demand; see the reports controller.)
  describe "demand we could not serve" do
    def unserved_ride
      trip = create(:trip)
      trip.transition_to!(:cancelled, actor: nil, actor_role: :admin, reason: "timed out")
      trip.update!(cancellation_reason: :no_courier_available)
      trip
    end

    def passenger_left
      trip = create(:trip)
      trip.transition_to!(:cancelled, actor: trip.passenger, actor_role: :customer)
      trip.update!(cancellation_reason: :passenger_changed_mind)
      trip
    end

    # THE POINT OF THE SPLIT. Both are cancellations and only one means hire
    # somebody. Summed, four rides "cancelled" says nothing; split, three say
    # there was nobody to send.
    it "counts a shortage apart from a passenger changing their mind" do
      3.times { unserved_ride }
      passenger_left

      get "/admin/reports"

      expect(unserved("Rides")).to eq(3), "the shortage is not counted, or churn is counted as shortage"
      expect(cancellation_count("Passenger changed mind", "Rides")).to eq(1)
    end

    # A zero here is the thing being watched — it says demand was met — so
    # unlike the ranked reasons this line is shown even when it is empty. An
    # absent row would read as "not measured".
    it "shows the line at zero rather than hiding it" do
      passenger_left

      get "/admin/reports"

      expect(unserved("Rides")).to eq(0)
      expect(response.body).to include("Every job asked for in this window found a courier")
    end

    it "keeps the shortage out of the ranked cancellation reasons" do
      2.times { unserved_ride }

      get "/admin/reports"

      expect(cancellation_count("No courier available", "Rides")).to be_nil,
                                                                    "the shortage is counted twice — once as " \
                                                                    "itself and once as an ordinary reason"
    end

    it "leaves an older cancellation out of the window" do
      old = unserved_ride
      old.update_column(:cancelled_at, 30.days.ago)

      get "/admin/reports"

      expect(unserved("Rides")).to eq(0)
    end

    # Deliveries and rides are different jobs and a reason belongs to one enum
    # or the other. Summing them would invent a word neither list contains.
    it "does not add a passenger's reason to a customer's" do
      passenger_left
      order = create(:order, :with_items)
      order.transition_to!(:cancelled, actor: order.customer, actor_role: :customer)
      order.update!(cancellation_reason: :customer_changed_mind)

      get "/admin/reports"

      expect(cancellation_count("Passenger changed mind", "Rides")).to eq(1)
      expect(cancellation_count("Passenger changed mind", "Deliveries")).to eq(0)
      expect(cancellation_count("Customer changed mind", "Deliveries")).to eq(1)
    end

    # Scoped to each table by heading, for the same reason the rejection helper
    # is: three tables on this page use identical markup.
    def section_table(heading)
      page = Nokogiri::HTML(response.body)
      node = page.css("h2").find { |h| h.text.include?(heading) }
      raise "no section headed #{heading}" if node.nil?

      node.xpath("following-sibling::table[1]").first
    end

    def unserved(column)
      cell_in(section_table("Demand we could not serve"), "Nobody available", column)
    end

    def cancellation_count(label, column)
      cell_in(section_table("Cancellations"), label, column)
    end

    def cell_in(table, row_label, column)
      index = table.css("thead th").map { |th| th.text.strip }.index(column)
      raise "no column #{column}" if index.nil?

      row = table.css("tbody tr").find { |tr| tr.css("td").first.text.strip.start_with?(row_label) }
      row && row.css("td")[index].text.strip.to_i
    end
  end

  # ── WHY SHOPS REFUSED WORK, AND WHETHER A PERSON REFUSED IT ────────────────
  #
  # The merchant board collects a reason from a fixed list because *"free text
  # would mean nobody can count why orders are refused"* — and for as long as it
  # has been collected, nothing counted it. `failure_reason` above is a
  # courier-side outcome and answers a different question entirely.
  describe "rejections" do
    # Both sides go through `transition_to!`, which is what the board's `reject`
    # action and `Dispatch::JobTimeoutsJob#close!` each call. Nothing here
    # stands in for the thing under test.
    def merchant_rejects(reason)
      owner = create(:user, :merchant_owner)
      order = create(:order, :with_items)
      order.transition_to!(:rejected, actor: owner, actor_role: :merchant_owner)
      order.update!(rejection_reason: reason)
      order
    end

    # Exactly what the timeout job does: **nil actor**, reason `no_answer`.
    def nobody_answers(reason: :no_answer)
      order = create(:order, :with_items)
      order.transition_to!(:rejected, actor: nil, actor_role: :admin,
                                      reason: "timed out in placed with no response")
      order.update!(rejection_reason: reason)
      order
    end

    it "counts the reasons merchants gave, which nothing did before" do
      2.times { merchant_rejects(:out_of_stock) }
      merchant_rejects(:too_busy)

      get "/admin/reports"

      expect(rejection_count("Out of stock")).to eq(2)
      expect(rejection_count("Too busy")).to eq(1)
    end

    # THE ONE THAT MATTERS. Three shops never looked at the tablet and one shop
    # made a decision. Added together the page says four shops keep closing
    # early, and the owner rings four restaurants about a problem three of them
    # do not have — while the real problem, a tablet nobody watches, is not on
    # the page at all.
    # THE ROWS ALREADY IN THE DATABASE. Until the job was corrected it wrote
    # `closing` on orders no shop had touched, and those rows do not go away —
    # eighty-one of them exist in the dev database. The split is by ACTOR, not
    # by reason, which is what makes it classify them correctly anyway. Planting
    # the legacy reason here is the assertion that it still does.
    it "does not count an order nobody answered as a shop that said it was closing" do
      merchant_rejects(:closing)
      3.times { nobody_answers(reason: :closing) }

      get "/admin/reports"

      expect(rejection_count("Closing")).to eq(1),
                                            "the timed-out orders are being counted as merchant decisions"
      expect(rejection_count("Nobody answered")).to eq(3),
                                                    "the orders nobody looked at are not on the page"
      expect(rejection_count("All rejected orders")).to eq(4)
    end

    # ── AN OPERATOR IS NOT A SHOP THAT NEVER PICKED UP ──────────────────────
    #
    # The split is by ACTOR, and a console operator has no `actor_id` — they are
    # an `AdminUser`. Until `StatusTransition#system?` counted both columns, a
    # rejection somebody at Karwan made looked exactly like a shop that never
    # answered, on the page whose job is deciding which shops to ring.
    #
    # Nothing in the console can reject an order today, so this builds the row
    # the way the model permits rather than through a route. It is here because
    # the day that route is added, this is the line that decides whether the
    # page blames a restaurant for it.
    it "does not count an operator's rejection as a shop that never answered" do
      3.times { nobody_answers }
      order = create(:order, :with_items)
      order.transition_to!(:rejected, actor: nil, admin_user: admin, actor_role: :admin,
                                      reason: "cancelled by operator")
      order.update!(rejection_reason: :other)

      get "/admin/reports"

      expect(rejection_count("Nobody answered")).to eq(3),
                                                    "a decision somebody at Karwan made is being blamed on a restaurant"
      expect(rejection_count("All rejected orders")).to eq(4)
    end

    it "says in words how much of the refusal rate is nobody looking" do
      merchant_rejects(:too_busy)
      3.times { nobody_answers }

      get "/admin/reports"

      expect(response.body).to include("75%")
      expect(response.body).to include("it was not looked at"),
                               "the figure needs its meaning beside it; a bare percentage reads as a kitchen problem"
    end

    # A merchant rejection with no reason on record is real — `rejection_reason`
    # is nullable and admin may reject through the console. It must not silently
    # become a timeout, so it appears in the total and nowhere else.
    it "does not mistake a merchant rejection with no reason for a timeout" do
      merchant_rejects(nil)

      get "/admin/reports"

      expect(rejection_count("Nobody answered")).to eq(0)
      expect(rejection_count("All rejected orders")).to eq(1)
    end

    # ── FOUND BY RENDERING IT, NOT BY READING IT ─────────────────────────
    #
    # The first version split two ways — a person, or the timeout — and against
    # the real database it announced eleven orders "closed by the timeout" that
    # have no transition row of any kind. Those are rows whose provenance was
    # never recorded, and saying the timeout closed them is a claim the data
    # does not support. A report that asserts a cause it cannot show is the
    # exact instrument `docs/TESTING.md` warns about.
    it "does not call an unrecorded rejection a timeout" do
      order = create(:order, :with_items)
      order.update!(status: :rejected, rejected_at: Time.current, rejection_reason: :too_busy)

      get "/admin/reports"

      expect(order.transitions.where(to_status: "rejected")).to be_empty,
                                                                "plant a row with no transition, or this proves nothing"
      expect(rejection_count("Nobody answered")).to eq(0),
                                                   "an order with no transition row is being blamed on the timeout"
      expect(rejection_count("Not recorded")).to eq(1)
      expect(rejection_count("Too busy")).to be_nil,
                                            "counted as a merchant decision, which nothing recorded"
    end

    # The good state has to be legible too: when every rejection was recorded,
    # the defect line is absent rather than a zero somebody has to interpret.
    it "hides the defect line when every rejection was recorded" do
      merchant_rejects(:too_busy)
      nobody_answers

      get "/admin/reports"

      expect(rejection_count("Not recorded")).to be_nil
      expect(response.body).not_to include("is a defect, not a business figure")
    end

    it "leaves an older rejection out of the window" do
      old = merchant_rejects(:out_of_stock)
      old.update_column(:rejected_at, 30.days.ago)

      get "/admin/reports"

      expect(rejection_count("Out of stock")).to be_nil
      expect(rejection_count("All rejected orders")).to eq(0)
    end

    # SCOPED TO THE RIGHT TABLE. The failure ranking below uses identical markup
    # under a similar heading, so a regex over the whole page would read a
    # number out of the wrong one and be believed.
    def rejection_count(label)
      page = Nokogiri::HTML(response.body)
      heading = page.css("h2").find { |h| h.text.include?("Why shops refused orders") }
      raise "the rejections table is not on the page" if heading.nil?

      table = heading.xpath("following-sibling::table[1]").first
      row = table.css("tbody tr").find { |tr| tr.css("td").first.text.strip.start_with?(label) }
      row && row.css("td").last.text.strip.to_i
    end
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
