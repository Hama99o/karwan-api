require "rails_helper"

# ═══ AFGHAN_UX §6: SHOW EVERYTHING ABOUT MONEY BEFORE IT IS OWED ═══════════
#
# *"Low institutional trust is a market condition, not a flaw to design around
# with cleverness. Be unambiguous instead."* Two of its four items were served
# to one side of the door and not the other.
RSpec.describe "what both sides know before the door opens" do
  let(:courier) { create(:user, :courier, name: "Ahmad Shah") }

  # § "The exact cash amount on the courier's screen AND the customer's, plus
  #   whether change is needed. People carry particular notes."
  describe "whether change is needed" do
    def order_totalling(total)
      create(:order, :with_items, :picked_up, courier: courier,
                                              items_total: total - 100, delivery_fee: 100,
                                              commission: 50, merchant_payout: total - 150,
                                              courier_fee: 100, customer_total: total)
    end

    it "tells the courier what note to be ready for" do
      steps = Couriers::JobSteps.new(order_totalling(450)).call
      collect = steps.find { |step| step[:key] == "collect_and_deliver" }

      expect(collect[:amount].to_f).to eq(450)
      expect(collect[:bring_change_for].to_f).to eq(500),
                                                "the man who has to produce the change is not told he will need it"
    end

    # THE SAME RULE AS THE CUSTOMER'S, from one place. Two screens advising
    # differently about one order is the failure this guards.
    it "says the same thing the customer is told" do
      order = order_totalling(1_250)

      collect = Couriers::JobSteps.new(order).call.find { |s| s[:key] == "collect_and_deliver" }
      customer = Customers::OrderSerializer.render_as_hash(order, view: :detailed)

      expect(collect[:bring_change_for]).to eq(customer[:suggested_notes])
      expect(collect[:bring_change_for].to_f).to eq(1_500), "the walkthrough's own figure"
    end

    # Quiet on a round hundred — a float already covers it, and advice nobody
    # needs is advice that stops being read.
    it "says nothing when no change is needed" do
      collect = Couriers::JobSteps.new(order_totalling(500)).call.find { |s| s[:key] == "collect_and_deliver" }

      expect(collect[:bring_change_for]).to be_nil
    end

    # ── REVERSED ON 23 SEPT 2026, AND THE OLD PIN IS KEPT HERE ─────────────
    #
    # This example used to assert that NO ride step carries `bring_change_for`,
    # for the stated reason: *"A ride collects a fare and advances nothing; the
    # step list is different and must not grow a delivery's field by accident."*
    #
    # The guard was against COPY-PASTE DRIFT and that half is right and is kept
    # below. The conclusion did not follow from it. *"A ride advances nothing"*
    # is the argument for having no PAY step — and it is correct for that. It
    # says nothing about the COLLECT step, because change advice is about the
    # cash taken at the door, not the cash put up at the shop.
    #
    # This file's own heading is what decided it: AFGHAN_UX §6, *"the exact cash
    # amount on the courier's screen AND the customer's, **plus whether change
    # is needed**. People carry particular notes."* That is a question about the
    # person who must produce change at a door, and a driver finishing a 160 AFN
    # fare against a 500 note is at that door. `CLAUDE.md` correction 8 puts
    # rides under the same model — *"the courier collects the fare in cash"* —
    # and its own policy list says *"no change → riders carry a change float."*
    #
    # Found by capturing the payload rather than by reading: the ride's collect
    # step simply had no such key, while the rider's on the same screen did.
    it "tells a driver about change too, on the step where cash changes hands" do
      trip = create(:trip, :in_progress, courier: courier, fare: 160, commission: 20,
                                  courier_earnings: 140)

      collect = Couriers::JobSteps.new(trip).call.find { |s| s[:key] == "complete_and_collect" }

      expect(collect[:bring_change_for].to_f).to eq(500),
                                                 "the driver is the one who has to produce it"
    end

    # THE HALF OF THE OLD PIN THAT WAS ALWAYS RIGHT, stated as what it meant.
    # A ride must not grow a DELIVERY's fields — the ones that describe
    # advancing money to a shop and finding a customer's door.
    it "still does not grow the fields a delivery has and a ride cannot" do
      trip = create(:trip, :in_progress, courier: courier, fare: 160, commission: 20,
                                  courier_earnings: 140)
      steps = Couriers::JobSteps.new(trip).call

      expect(steps.map { |step| step[:amount_direction] }).not_to include("pay"),
                                                                 "a driver is being asked to hand a passenger money"
      expect(steps.flat_map(&:keys).uniq).not_to include(:has_voice_note, :voice_note_url, :place_name)
    end
  end

  # § "The courier's name and photo before they arrive — for the customer, and
  #   especially for a woman expecting a stranger at the door."
  describe "who is at the door" do
    let(:order) { create(:order, :with_items, :picked_up, courier: courier) }

    def attach_avatar!
      courier.avatar.attach(io: File.open(Rails.root.join("spec/fixtures/files/photo.png")),
                            filename: "avatar.png", content_type: "image/png")
    end

    it "sends the courier's face on the order screen" do
      attach_avatar!

      payload = Customers::OrderSerializer.render_as_hash(order.reload, view: :detailed)

      expect(payload[:courier][:name]).to eq("Ahmad")
      expect(payload[:courier][:photo_url]).to be_present,
                                               "a customer cannot see who is coming to their door"
    end

    # The payload open WHILE he is on his way, which is where it matters most.
    it "sends it on the tracking screen too" do
      attach_avatar!

      payload = Customers::TrackSerializer.render_as_hash(order.reload)

      expect(payload[:courier][:photo_url]).to be_present
    end

    # THE COMMON CASE UNTIL COURIERS ARE ASKED FOR A PHOTO AT ONBOARDING. Nil,
    # not a broken URL — a 404 on a face is worse than an initial.
    it "is nil when he has not set one" do
      payload = Customers::OrderSerializer.render_as_hash(order, view: :detailed)

      expect(payload[:courier][:photo_url]).to be_nil
    end

    # ── STILL FIRST NAME ONLY, AND BOUNDED BY THE KEY SET ─────────────────
    #
    # Written first as `expect(payload[:courier][:name]).not_to include("Shah")`,
    # which guards ONE key. Planting a second key — `full_name:` beside the
    # photo — left it green, because nothing said what the object may contain.
    # An example named "does not start sending his full name" that reads only
    # `name` is checking the wrong thing.
    #
    # So this asserts the whole shape, as `payload_key_sets_spec` does for the
    # payloads themselves: three keys, and his surname in none of them.
    it "does not start sending more of his identity with it" do
      attach_avatar!

      courier_block = Customers::OrderSerializer.render_as_hash(order.reload, view: :detailed)[:courier]

      expect(courier_block.keys.map(&:to_s).sort).to eq(%w[name phone photo_url]),
                                                     "the courier object grew a field — adding one here is adding " \
                                                     "it to what every customer knows about the man at their door"
      expect(courier_block.values.join(" ")).not_to include("Shah")
    end
  end
end
