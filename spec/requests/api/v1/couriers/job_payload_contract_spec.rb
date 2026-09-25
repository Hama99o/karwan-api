require "rails_helper"

# ═══ THE COURIER'S ACTIVE JOB, CAPTURED IN BOTH SHAPES ═════════════════════
#
# `settlements_payload_contract_spec.rb` states the argument: *"A description is
# an intention; a response is a fact, and the two drift silently."* This is the
# payload with the most shape to get wrong in the whole API, and the one where
# getting it wrong costs the most:
#
#   · it is the ONE screen a courier uses one-handed, in motion, in sunlight
#   · it carries MONEY IN TWO DIRECTIONS — he hands over `merchant_payout` and
#     collects `customer_total`, and is out of pocket in between
#   · correction 7 makes it the seam a third demand type arrives through: a
#     delivery is four steps, a ride is three, **from one screen**
#
# ── WHY TWO FILES AND NOT ONE ─────────────────────────────────────────────
#
# A fixture is worth having because it IS the response, byte for byte. The
# endpoint serves one job, so two shapes means two captures:
#
#   spec/fixtures/files/courier_job_delivery.json   four steps, a pay and a collect
#   spec/fixtures/files/courier_job_ride.json       three steps, collect only
#
# The third state — no job at all — is `{"job": null}` and is asserted inline,
# because a two-key file teaches nothing a sentence cannot.
#
# ── THE FOUR DISTINCTIONS, AND WHAT EACH COSTS A CLIENT THAT COLLAPSES IT ──
#
#   1. **A ride has no pay step.** Nothing is advanced, which is why a courier
#      too short for a delivery can still take a ride. A client that renders a
#      pay step from a template asks a driver to hand a passenger money.
#   2. **`amount_direction` is the whole meaning of `amount`.** `pay` and
#      `collect` are the same field and opposite acts. Reading the number
#      without the direction is how a courier collects 350 and hands over 500.
#   3. **A navigation step has `status_after: null` and cannot be completed by
#      itself.** "Go to the merchant" carries no transition — it is done when
#      the step it leads to is done. A client that offers a button for it
#      produces a step that stays current forever, which is what the first
#      version of `JobSteps` did.
#   4. **`bring_change_for` is nil on a round hundred**, and nil means "a float
#      covers it", not "no information". It exists on the delivery's collect
#      step and on no step of a ride.
#
# Every label here is an i18n KEY, never English: the server cannot say "collect
# the cash" in Pashto, and `AFGHAN_UX.md` makes the client hold the words.
RSpec.describe "the courier job contract", type: :request do
  let(:courier) { create(:user, :courier) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(courier).last}" } }
  let(:merchant) do
    create(:merchant, name: "کباب شهر نو", latitude: 34.5553, longitude: 69.2075,
                      landmark_note: "دروازه آبی، نزدیک پارک")
  end

  # Fixed instant: `at` is in the payload on every completed step, so a live
  # clock would make the fixture need regenerating hourly.
  let(:evening_in_kabul) { Time.zone.parse("2026-09-22 20:00:00 +0430") }

  before do
    courier.courier_profile.update!(is_available: true, accepted_job_kinds: %w[delivery ride],
                                    last_latitude: 34.5553, last_longitude: 69.2075,
                                    location_updated_at: Time.current)
    courier.courier_wallet.update!(balance: 5_000, credit_line: 500)
  end

  def fixture(name)
    JSON.parse(Rails.root.join("spec/fixtures/files/#{name}.json").read)
  end

  # PICKED UP, not ready: it is the state where the list is most informative —
  # two steps behind him, one current, one ahead — and it is the state where the
  # courier is carrying our money and the shop has been paid.
  def delivery!
    order = create(:order, :with_items, :picked_up, merchant: merchant, courier: courier,
                                                    code: "K000042", items_total: 400,
                                                    delivery_fee: 100, customer_total: 500,
                                                    commission: 50, courier_fee: 100,
                                                    merchant_payout: 350,
                                                    delivery_latitude: 34.5310, delivery_longitude: 69.1680,
                                                    delivery_landmark_note: "منزل سوم، پشت مسجد")
    %w[accepted preparing ready picked_up].each do |reached|
      order.transitions.create!(to_status: reached, actor_role: :merchant_owner, created_at: Time.current)
    end
    order
  end

  def ride!
    trip = create(:trip, :accepted, courier: courier, code: "R000042", fare: 160,
                                    commission: 20, courier_earnings: 140,
                                    pickup_latitude: 34.5553, pickup_longitude: 69.2075,
                                    pickup_landmark_note: "سرک دوم، کنار نانوایی",
                                    dropoff_latitude: 34.5100, dropoff_longitude: 69.1550,
                                    dropoff_landmark_note: "چهارراهی، مقابل دواخانه")
    trip.transitions.create!(to_status: "accepted", actor_role: :courier, created_at: Time.current)
    trip
  end

  # Stand-ins for the two things a fixture must never pin, both of which come
  # from a counter that keeps climbing across a run rather than from the payload:
  # the row id and the factory's phone sequence. Caught twice in one night — see
  # `docs/TESTING.md`, "a committed payload fixture must not pin a
  # database-assigned id".
  MERCHANT_PHONE = "+93780000000".freeze
  PERSON_PHONE = "+93770000000".freeze

  # `phones` maps each real number to its placeholder. Every one is ASSERTED to
  # be in the payload before it is replaced: that each step names the person the
  # courier has to ring is the contract, and normalising it away unchecked would
  # delete the only thing the field is for.
  # `phones` is passed only by the two examples that compare against a file.
  # Nil means "leave them alone" — the targeted examples below assert on step
  # contents and have no reason to care what number is in them.
  def job_payload(phones: nil)
    get "/api/v1/courier/job", headers: auth
    expect(response).to have_http_status(:ok), "not the job payload at all: #{response.body[0, 160]}"
    body = JSON.parse(response.body)
    body["job"]["id"] = 1 if body.dig("job", "id")
    return body if phones.nil?

    served = body.dig("job", "steps").to_a.filter_map { |step| step["phone"] }.uniq
    expect(served).to match_array(phones.keys), "a step names a phone number that is nobody's in this job"
    body["job"]["steps"].each { |step| step["phone"] = phones[step["phone"]] if step["phone"] }
    body
  end

  it "matches the captured delivery, field for field" do
    travel_to(evening_in_kabul) do
      delivery!

      expect(job_payload(phones: { merchant.phone => MERCHANT_PHONE,
                                   Order.last.customer_phone => PERSON_PHONE }))
        .to eq(fixture("courier_job_delivery")),
                             "the courier job payload changed. If deliberate, regenerate " \
                             "spec/fixtures/files/courier_job_delivery.json and tell the mobile session — " \
                             "this is the screen a courier uses while carrying our money."
    end
  end

  it "matches the captured ride, field for field" do
    travel_to(evening_in_kabul) do
      trip = ride!

      expect(job_payload(phones: { trip.passenger_phone => PERSON_PHONE }))
        .to eq(fixture("courier_job_ride")),
                             "the courier job payload changed. If deliberate, regenerate " \
                             "spec/fixtures/files/courier_job_ride.json and tell the mobile session."
    end
  end

  # ── 1 · A RIDE ADVANCES NOTHING, SO IT HAS NO PAY STEP ───────────────────
  it "gives a delivery a pay step and a ride none" do
    travel_to(evening_in_kabul) do
      delivery!
      delivery_steps = job_payload["job"]["steps"]
      Order.destroy_all
      ride!
      ride_steps = job_payload["job"]["steps"]

      expect(delivery_steps.length).to eq(4)
      expect(ride_steps.length).to eq(3)
      expect(delivery_steps.map { |s| s["amount_direction"] }).to include("pay")
      expect(ride_steps.map { |s| s["amount_direction"] }).not_to include("pay"),
                                                                 "a driver is being asked to hand a passenger money"
    end
  end

  # ── 2 · THE DIRECTION IS THE MEANING ─────────────────────────────────────
  it "pays the merchant their payout and collects the customer's total" do
    travel_to(evening_in_kabul) do
      order = delivery!
      steps = job_payload["job"]["steps"].index_by { |s| s["key"] }

      expect(steps["pay_merchant"]["amount"]).to eq(order.merchant_payout.to_s)
      expect(steps["pay_merchant"]["amount_direction"]).to eq("pay")
      expect(steps["collect_and_deliver"]["amount"]).to eq(order.customer_total.to_s)
      expect(steps["collect_and_deliver"]["amount_direction"]).to eq("collect")
      # The two are DIFFERENT numbers and the gap is what he is owed back.
      expect(steps["pay_merchant"]["amount"]).not_to eq(steps["collect_and_deliver"]["amount"])
    end
  end

  # ── 3 · A NAVIGATION STEP CARRIES NO ACTION ──────────────────────────────
  it "gives navigation steps no status_after and exactly one step is current" do
    travel_to(evening_in_kabul) do
      delivery!
      steps = job_payload["job"]["steps"]

      navigation = steps.select { |s| s["status_after"].nil? }
      expect(navigation.map { |s| s["key"] }).to eq(%w[go_to_merchant go_to_customer])
      expect(steps.count { |s| s["current"] }).to eq(1),
                                                 "the screen shows one action at a time and the server decides which"
    end
  end

  # ── 4 · NIL CHANGE ADVICE IS ADVICE ──────────────────────────────────────
  it "advises on change only where cash is collected" do
    travel_to(evening_in_kabul) do
      delivery!
      steps = job_payload["job"]["steps"]

      carrying = steps.select { |s| s.key?("bring_change_for") }
      expect(carrying.map { |s| s["key"] }).to eq(%w[collect_and_deliver]),
                                               "change advice belongs on the step where cash changes hands"
      # 500 is a round hundred: nil here means a float covers it, NOT that
      # nothing is known. Same rule the customer is given, from the same method.
      expect(steps.last["bring_change_for"]).to be_nil
    end
  end

  # ── AND THE SAME ADVICE ON A RIDE, WHICH IS THE SAME CASH PROBLEM ───────
  #
  # `CLAUDE.md` correction 8: *"Model A applies to rides too — same wallet, same
  # commission, simpler flow"*, and the courier *"collects the fare in cash"*.
  # `AFGHAN_UX.md` §6 asks for *"the exact cash amount on the courier's screen
  # AND the customer's, plus whether change is needed"* — of the courier, not of
  # the demand type.
  #
  # A 160 AFN fare paid with a 500 note is the same doorstep as a 160 AFN order.
  # MEASURED: `Monetary.change_advice(160)` is 500, so there IS advice to give.
  it "tells a driver about change too, not only a rider" do
    travel_to(evening_in_kabul) do
      trip = ride!
      collect = job_payload["job"]["steps"].detect { |s| s["amount_direction"] == "collect" }

      expect(collect["amount"]).to eq(trip.fare.to_s)
      expect(collect).to have_key("bring_change_for"),
                         "the ride's cash step carries no change advice at all, so a driver collecting " \
                         "an odd fare is never told to carry a float — the rider on the same screen is"
      expect(collect["bring_change_for"]).to eq("500.0"),
                                            "160 is not a round hundred and the same rule the customer is given says 500"
    end
  end

  # ── THE CHANGE HANDED BACK IS THE SERVER'S NUMBER ───────────────────────
  #
  # The app used to subtract `bring_change_for - amount` itself (karwan-42,
  # 25 Sept 2026), which made the cash a courier hands a customer at a door the
  # one money figure computed off the server. `Monetary.change_at_the_door`
  # now yields the note and the change from one total.
  it "sends the change due, so no phone subtracts" do
    travel_to(evening_in_kabul) do
      ride!
      collect = job_payload["job"]["steps"].last

      expect(collect["change_due"]).to eq("340.0")
      expect(collect["change_due"].to_d + collect["amount"].to_d).to eq(collect["bring_change_for"].to_d)
    end
  end

  # ── EVERY AMOUNT IS A STRING, INCLUDING THE ADVICE ABOUT ONE ─────────────
  #
  # `docs/API_VOCABULARY.md`: *"every amount is a JSON string ("500.0",
  # "-50.0"), never a number."* `Monetary.change_advice` broke it in three
  # payloads at once — `.ceil` on a BigDecimal returns an Integer — and every
  # committed example had a round hundred, so all three served `nil` and nobody
  # saw a bare `500` sitting next to `"445.0"`.
  #
  # Asserted here across BOTH sides of one helper, because the courier's step
  # and the customer's `suggested_notes` are the same rule and must not drift.
  it "serialises change advice the way it serialises every other amount" do
    travel_to(evening_in_kabul) do
      ride!
      collect = job_payload["job"]["steps"].last

      expect(collect["bring_change_for"]).to be_a(String)
      expect(collect["bring_change_for"]).to eq(collect["bring_change_for"].to_d.to_s),
                                            "an amount beside amounts, in a different shape"
    end
  end

  it "gives the customer the same shape for the same advice" do
    travel_to(evening_in_kabul) do
      customer = create(:user, :customer)
      order = create(:order, :with_items, customer: customer, merchant: merchant,
                                          items_total: 345, delivery_fee: 100, customer_total: 445,
                                          commission: 50, merchant_payout: 295, courier_fee: 100)

      get "/api/v1/customer/orders/#{order.id}",
          headers: { "Authorization" => "Bearer #{UserSession.issue!(customer).last}" }

      expect(response).to have_http_status(:ok), "not the order payload: #{response.body[0, 160]}"
      body = JSON.parse(response.body)["order"]
      expect(body["suggested_notes"]).to eq("500.0"),
                                         "the customer is told to bring a note in a different shape from every other amount"
      expect(body["customer_total"]).to be_a(String)
    end
  end

  # ── THE EMPTY CASE, WHICH IS A SHAPE TOO ─────────────────────────────────
  it "sends job: null rather than an empty object or a 404" do
    get "/api/v1/courier/job", headers: auth

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq({ "job" => nil }),
                                         "a courier with nothing to do is not an error and not an empty object"
  end

  # The fixtures must keep teaching both shapes. A regeneration that quietly
  # loses one leaves the client with a shape it will meet on a real shift.
  it "keeps both shapes in the fixtures" do
    delivery = fixture("courier_job_delivery")["job"]["steps"]
    ride = fixture("courier_job_ride")["job"]["steps"]

    expect(delivery.length).to eq(4)
    expect(ride.length).to eq(3)
    expect(delivery.map { |s| s["label_key"] }).to all(start_with("courier.steps.")),
                                                  "a label became English, which no device can translate"
    expect(ride.map { |s| s["label_key"] }).to all(start_with("courier.steps."))
  end
end
