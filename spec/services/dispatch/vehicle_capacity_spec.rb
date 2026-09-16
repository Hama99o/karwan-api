require "rails_helper"

# A BED AND A BOOK ARE NOT THE SAME DELIVERY.
#
# Nothing in the system expressed how big a delivery was, so a bulky order
# could be offered to a courier on a bicycle. He would accept it in good faith,
# ride there, and find he could not carry it — a failure that costs the
# customer, the merchant and the courier at once, and the only party who could
# have known is us.
#
# Hamma9900 added `zarang` (a rishka built for heavy goods; his example is a
# bed) for exactly this. The capacity map is PROVISIONAL — see
# `CourierProfile::CARRIES` — so these examples assert the MECHANISM, and use
# the two ends of the scale where the ordering is not in doubt.
RSpec.describe "how big a delivery is" do
  let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075) }
  let(:category) { create(:catalog_category, merchant: merchant) }

  def item(size_class, price: 400)
    create(:catalog_item, catalog_category: category, merchant: merchant,
                          price: price, size_class: size_class)
  end

  def courier_with(vehicle)
    user = create(:user, :courier)
    user.courier_profile.update!(
      vehicle_type: vehicle, is_available: true, accepted_job_kinds: %w[delivery ride],
      last_latitude: 34.5553, last_longitude: 69.2075, location_updated_at: Time.current
    )
    user.courier_wallet.update!(balance: 10_000, credit_line: 500)
    user
  end

  def place(*items)
    Orders::PlaceService.new(
      customer: create(:user, :customer), merchant: merchant,
      lines: items.map { |i| { catalog_item_id: i.id, quantity: 1 } },
      delivery_latitude: 34.5600, delivery_longitude: 69.2100
    ).call
  end

  describe "the scale itself" do
    it "orders the four sizes, smallest first" do
      expect(SizeClasses::ALL).to eq(small: 0, medium: 1, large: 2, bulky: 3)
    end

    # FOOD IS SMALL, and it is the default — so every row that existed before
    # this column means "small", which is true of everything ordered so far.
    it "defaults an item to the smallest size" do
      expect(create(:catalog_item).size_class).to eq("small")
    end

    it "defaults an order to the smallest size" do
      expect(create(:order).required_size_class).to eq("small")
    end
  end

  describe "what an order needs" do
    # A bulky order cannot even be PLACED unless somebody owns a zarang — which
    # is the refusal below, and the reason it has to be set up here. The first
    # version of this spec forgot, and the guard failed it correctly.
    before { courier_with(:zarang) }

    # THE SNAPSHOT. The largest thing in the basket decides the vehicle.
    it "takes the largest item in the basket" do
      order = place(item(:small), item(:bulky), item(:medium))

      expect(order.required_size_class).to eq("bulky")
    end

    it "stays small for a basket of food" do
      expect(place(item(:small), item(:small)).required_size_class).to eq("small")
    end

    # One-way door #1, applied to size rather than to price: a merchant
    # re-classifying an item must not change what a past order needed, or a
    # completed delivery becomes unexplainable.
    it "does not change when the merchant re-classifies the item afterwards" do
      bed = item(:bulky)
      order = place(bed)

      bed.update!(size_class: :small)

      expect(order.reload.required_size_class).to eq("bulky")
    end
  end

  describe "who can be offered it" do
    before { courier_with(:zarang) }

    let(:bulky_order) { place(item(:bulky)) }
    let(:food_order) { place(item(:small)) }

    def reason_for(courier, job)
      Dispatch::Eligibility.new(courier: courier, job: job).reason
    end

    it "refuses a bicycle a bulky order" do
      expect(reason_for(courier_with(:bicycle), bulky_order)).to eq(:vehicle_too_small)
    end

    it "refuses a motorbike a bulky order" do
      expect(reason_for(courier_with(:motorbike), bulky_order)).to eq(:vehicle_too_small)
    end

    it "offers a zarang the bulky order" do
      expect(reason_for(courier_with(:zarang), bulky_order)).to be_nil
    end

    it "offers a bicycle the food" do
      expect(reason_for(courier_with(:bicycle), food_order)).to be_nil
    end

    # ── THE EXAMPLE THAT DISTINGUISHES THE TWO IMPLEMENTATIONS ──────────────
    #
    # Rewriting this check to read the LIVE catalog instead of the frozen
    # requirement broke nothing: every other fixture had the two agreeing, so
    # both implementations gave the same answer. `docs/TESTING.md` states the
    # rule this is an instance of — a test that a value is STORED correctly is
    # not a test that anything READS it. So: freeze the copy, mutate the
    # source, and assert the CONSUMER's behaviour.
    it "keeps refusing the bicycle after the merchant re-classifies the item" do
      bed = item(:bulky)
      order = place(bed)
      bicycle = courier_with(:bicycle)

      bed.update!(size_class: :small)

      expect(reason_for(bicycle, order.reload)).to eq(:vehicle_too_small)
    end

    # And the mirror, so the test cannot pass by refusing everybody: a zarang
    # is still offered the same order.
    it "keeps offering the zarang the same order" do
      bed = item(:bulky)
      order = place(bed)
      bed.update!(size_class: :small)

      expect(reason_for(courier_with(:zarang), order.reload)).to be_nil
    end

    it "explains itself, so an ops console can say why work went unassigned" do
      eligibility = Dispatch::Eligibility.new(courier: courier_with(:bicycle), job: bulky_order)

      expect(eligibility.explanation).to eq("courier's vehicle cannot carry this order")
    end

    # A ride is people, not goods. Asking a Trip its size must not raise, and
    # must not refuse a motorbike a passenger.
    it "does not ask a ride how big it is" do
      expect(reason_for(courier_with(:motorbike), create(:trip))).to be_nil
    end

    # Fails CLOSED: a vehicle added to the enum with no capacity entry is one
    # nobody should be offered a bulky job on. A missing entry costs a dispatch;
    # failing open would cost a courier a wasted journey.
    it "refuses a vehicle whose capacity nobody has declared" do
      courier = courier_with(:bicycle)
      courier.courier_profile.update_column(:vehicle_type, 99)

      expect(courier.courier_profile.reload.carries?(:small)).to be false
    end
  end

  # ── THE TWO QUESTIONS THAT LOOK ALIKE ──────────────────────────────────────
  #
  # "Nobody owns a vehicle that could carry this" is permanent and an honest
  # refusal. "No suitable vehicle is online right now" is a five-minute problem
  # and must NOT refuse, or a delivery we could have had becomes a customer who
  # leaves.
  describe "refusing at placement, when nothing in the fleet can carry it" do
    it "refuses a bulky order when the whole fleet is motorbikes" do
      courier_with(:motorbike)

      expect { place(item(:bulky)) }.to raise_error(Orders::PlaceService::NoVehicleForOrder)
    end

    it "writes no order at all" do
      courier_with(:motorbike)
      bed = item(:bulky)

      expect { place(bed) rescue nil }.not_to change(Order, :count)
    end

    it "places it when somebody owns a zarang, even one who is offline" do
      owner = courier_with(:zarang)
      owner.courier_profile.update!(is_available: false)

      expect(place(item(:bulky))).to be_persisted
    end

    # An applicant with a zarang is not the fleet — they cannot be dispatched
    # to anything, so their vehicle cannot make an order placeable.
    it "does not count an unapproved applicant's vehicle" do
      applicant = courier_with(:zarang)
      applicant.courier_profile.update!(verification_status: :pending)

      expect { place(item(:bulky)) }.to raise_error(Orders::PlaceService::NoVehicleForOrder)
    end

    it "never refuses food, whoever is on the platform" do
      expect(place(item(:small))).to be_persisted
    end
  end

  describe "warning at quote time, when nothing suitable is online" do
    def quote(*items)
      Orders::QuoteService.new(
        merchant: merchant, lines: items.map { |i| { catalog_item_id: i.id, quantity: 1 } },
        delivery_latitude: 34.5600, delivery_longitude: 69.2100
      ).call
    end

    it "warns when the only capable vehicle is offline" do
      courier_with(:zarang).courier_profile.update!(is_available: false)

      expect(quote(item(:bulky)).dispatch_warning).to eq("no_vehicle_online")
    end

    it "says nothing when a capable vehicle is online" do
      courier_with(:zarang)

      expect(quote(item(:bulky)).dispatch_warning).to be_nil
    end

    it "says nothing about food, ever" do
      expect(quote(item(:small)).dispatch_warning).to be_nil
    end

    # The warning is recomputed per quote rather than frozen, so a zarang
    # coming online five minutes later makes it disappear — which is the whole
    # reason this is a warning and not a stored refusal.
    it "goes away when a capable courier comes on shift" do
      zarang = courier_with(:zarang)
      zarang.courier_profile.update!(is_available: false)
      bed = item(:bulky)

      expect(quote(bed).dispatch_warning).to eq("no_vehicle_online")
      zarang.courier_profile.update!(is_available: true)
      expect(quote(bed).dispatch_warning).to be_nil
    end
  end

  # ── THE PEOPLE AXIS ─────────────────────────────────────────────────────────
  #
  # The same shape as cargo size, on a different quantity. It is in v0 because
  # it is the first piece of multi-job (correction 19) and because without it a
  # family of four could agree a motorbike fare and be undispatchable.
  describe "how many people are travelling" do
    def reason_for(courier, job)
      Dispatch::Eligibility.new(courier: courier, job: job).reason
    end

    it "refuses a motorbike four passengers" do
      trip = create(:trip, passenger_count: 4)

      expect(reason_for(courier_with(:motorbike), trip)).to eq(:too_many_passengers)
    end

    it "offers a car the same four" do
      trip = create(:trip, passenger_count: 4, vehicle_type: :car)

      expect(reason_for(courier_with(:car), trip)).to be_nil
    end

    it "offers a motorbike one passenger" do
      expect(reason_for(courier_with(:motorbike), create(:trip, passenger_count: 1))).to be_nil
    end

    # Nobody rides pillion on a bicycle, and `on_foot` carries parcels.
    it "refuses a bicycle any passenger at all" do
      trip = create(:trip, passenger_count: 1)

      expect(reason_for(courier_with(:bicycle), trip)).to eq(:too_many_passengers)
    end

    it "refuses more people than any vehicle seats, at the model" do
      expect(build(:trip, passenger_count: 9)).not_to be_valid
      expect(build(:trip, passenger_count: 0)).not_to be_valid
    end

    it "lists only the classes that seat the party, so a family never sees a motorbike fare" do
      expect(CourierProfile.vehicle_types_seating(4)).to eq([ "car" ])
      expect(CourierProfile.vehicle_types_seating(1)).to include("motorbike", "rishka", "car")
      expect(CourierProfile.vehicle_types_seating(1)).not_to include("bicycle", "on_foot")
    end
  end

  # ── THE CLASS THE PASSENGER PAID FOR ───────────────────────────────────────
  #
  # Part of what was agreed, which is why the fare could depend on the vehicle
  # and still be quoted upfront. A bigger vehicle is NOT a free upgrade: that
  # driver would earn motorbike money, decline, and the customer would pay for
  # the wasted TTL in waiting.
  describe "matching the vehicle class a passenger chose" do
    def reason_for(courier, job)
      Dispatch::Eligibility.new(courier: courier, job: job).reason
    end

    it "offers a car trip to a car" do
      expect(reason_for(courier_with(:car), create(:trip, vehicle_type: :car))).to be_nil
    end

    it "refuses a motorbike a trip that asked for a car" do
      expect(reason_for(courier_with(:motorbike), create(:trip, vehicle_type: :car)))
        .to eq(:wrong_vehicle_class)
    end

    it "refuses a car a trip that asked for a motorbike, rather than treating it as an upgrade" do
      trip = create(:trip, vehicle_type: :motorbike, passenger_count: 1)

      expect(reason_for(courier_with(:car), trip)).to eq(:wrong_vehicle_class)
    end

    # Trips booked before classes existed chose nothing, and must stay
    # dispatchable to anybody rather than becoming undeliverable.
    it "offers a trip with no class to any courier" do
      trip = create(:trip, vehicle_type: nil, passenger_count: 1)

      expect(reason_for(courier_with(:motorbike), trip)).to be_nil
      expect(reason_for(courier_with(:car), trip)).to be_nil
    end

    it "asks a delivery nothing about class or seats" do
      order = place(item(:small))

      expect(reason_for(courier_with(:car), order)).to be_nil
    end
  end
end
