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

    # A ride collects a fare and advances nothing; the step list is different
    # and must not grow a delivery's field by accident.
    it "leaves the ride steps alone" do
      trip = create(:trip, :in_progress, courier: courier)

      Couriers::JobSteps.new(trip).call.each do |step|
        expect(step).not_to have_key(:bring_change_for)
      end
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
