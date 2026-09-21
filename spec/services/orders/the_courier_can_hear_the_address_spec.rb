require "rails_helper"

# ── R12: FOR MANY CUSTOMERS THE RECORDING *IS* THE ADDRESS ─────────────────
#
# "A large share of Afghan adults cannot read fluently… Typing 'the blue gate
# near the mosque, second floor' in Pashto is the hardest single action in the
# order flow; SAYING it is trivial. So an address is a pin, a voice note, and a
# phone number, with the text field optional rather than primary."
#
# `addresses` has carried the recording since that was built and the customer's
# app can play it back. The ORDER never copied it, and
# `Couriers::JobSteps` sent `has_voice_note: false` as a literal — so the one
# person who has to find the door was told there was no recording, on every
# order, since the day the feature shipped.
RSpec.describe "the courier can hear the address" do
  let(:customer) { create(:user, :customer) }
  let(:merchant) { create(:merchant) }

  # Seconds are set AFTER the attach, the way a real client does it: Address
  # has `before_save :sync_voice_note_flag`, which nils `voice_note_seconds`
  # whenever no recording is attached. Setting it at create time — which the
  # first version of this helper did — is silently discarded, and the resulting
  # nil would have looked like a bug in the copy rather than in the fixture.
  def address_with_voice_note(seconds: 12)
    address = create(:address, user: customer)
    address.voice_note.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/voice_note.m4a")),
      filename: "voice_note.m4a", content_type: "audio/mp4"
    )
    address.update!(voice_note_seconds: seconds)
    address
  end

  def place(address: nil)
    item = create(:catalog_item, merchant: merchant, price: 400)
    Orders::PlaceService.new(
      customer: customer, merchant: merchant,
      lines: [ { catalog_item_id: item.id, quantity: 1 } ],
      delivery_address: address,
      delivery_latitude: 34.5553, delivery_longitude: 69.2075,
      delivery_landmark_note: "blue gate", customer_phone: customer.phone
    ).call
  end

  it "copies the recording onto the order" do
    order = place(address: address_with_voice_note)

    expect(order.delivery_voice_note).to be_attached
    expect(order.delivery_voice_note_seconds).to eq(12)
  end

  # ── A COPY, NOT A POINTER ───────────────────────────────────────────────
  #
  # Attaching the address's own blob would break the moment the customer
  # re-records: replacing an attachment purges the old one, silently emptying
  # every past order that pointed at it. That is exactly what "the address is
  # COPIED, not referenced" exists to prevent.
  it "survives the customer re-recording their door instructions" do
    address = address_with_voice_note
    order = place(address: address)

    address.voice_note.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/voice_note.m4a")),
      filename: "second_take.m4a", content_type: "audio/mp4"
    )

    expect(order.reload.delivery_voice_note).to be_attached,
                                                "the order lost its recording when the customer re-recorded"
    expect(order.delivery_voice_note.blob_id).not_to eq(address.reload.voice_note.blob_id),
                                                     "the order points at the address's blob rather than a copy"
  end

  it "tells the courier there is one, and how long, and where to play it" do
    courier = create(:user, :courier)
    order = place(address: address_with_voice_note)
    order.update!(courier: courier)

    step = Couriers::JobSteps.new(order).call.find { |s| s[:key] == "go_to_customer" }

    expect(step[:has_voice_note]).to be(true), "the literal false is still there"
    expect(step[:voice_note_seconds]).to eq(12)
    expect(step[:voice_note_url]).to be_present
  end

  # A URL that 404s is worse than none: the courier taps it at a junction and
  # learns only that the app is unreliable.
  it "offers no url when there is no recording" do
    courier = create(:user, :courier)
    order = place
    order.update!(courier: courier)

    step = Couriers::JobSteps.new(order).call.find { |s| s[:key] == "go_to_customer" }

    expect(step[:has_voice_note]).to be(false)
    expect(step[:voice_note_url]).to be_nil
  end

  # A ride has no delivery address and no recording; asking must not raise.
  it "is quiet on a ride rather than raising" do
    trip = create(:trip, :accepted, courier: create(:user, :courier))

    expect { Couriers::JobSteps.new(trip).call }.not_to raise_error
  end

  # ── A LOST RECORDING MUST NOT LOSE THE ORDER ────────────────────────────
  #
  # Without the recording the courier still has the pin, the landmark text and a
  # phone number — the state every order was in until today. Failing the order
  # instead would trade a degraded delivery for no delivery.
  it "still places the order if the copy fails" do
    address = address_with_voice_note
    allow_any_instance_of(ActiveStorage::Blob).to receive(:download).and_raise(StandardError, "storage down")

    order = nil
    expect { order = place(address: address) }.not_to raise_error
    expect(order).to be_persisted
    expect(order.delivery_voice_note).not_to be_attached
  end

  # The id is used for the recording only. Every other field comes from the
  # parameters, so an address cannot make the order say a different place.
  it "does not take the pin or the landmark from the address" do
    address = create(:address, user: customer, latitude: 30.0, longitude: 60.0,
                               landmark_note: "somewhere else entirely")

    order = place(address: address)

    expect(order.delivery_latitude.to_f).to eq(34.5553)
    expect(order.delivery_landmark_note).to eq("blue gate")
  end
end
