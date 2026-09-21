require "rails_helper"

# ── WHEN A COURIER WAS AVAILABLE ───────────────────────────────────────────
#
# `PRODUCT.md` calls orders per rider per day "the number that decides the
# business". Without shift history the only available denominator is couriers
# who COMPLETED a job, so a courier who was online all day and took nothing is
# invisible and the figure flatters the business — the wrong direction for a
# hiring decision.
#
# `courier_profiles.is_available` is a switch with no history, so this was not
# merely unbuilt, it was **unrecoverable**: every day without the table is a day
# whose idle capacity can never be known. That is `CLAUDE.md`'s one-way door —
# what you fail to record cannot be reconstructed.
RSpec.describe "a courier's availability is recorded" do
  let(:courier) { create(:user, :courier) }
  let(:profile) { courier.courier_profile }

  before { profile.update_column(:is_available, false) }

  it "opens a shift when they go on" do
    expect { profile.set_availability!(true) }.to change { courier.courier_shifts.count }.by(1)

    shift = courier.courier_shifts.last
    expect(shift.started_at).to be_present
    expect(shift.ended_at).to be_nil, "a shift that is still running must not carry an end"
  end

  it "closes it when they go off" do
    profile.set_availability!(true)

    travel_to 4.hours.from_now do
      profile.set_availability!(false)
    end

    shift = courier.courier_shifts.last
    expect(shift.ended_at).to be_present
    expect(shift.hours).to be_within(0.05).of(4.0)
  end

  # ── THE RETRY, AGAIN ────────────────────────────────────────────────────
  #
  # The courier's app sends this toggle on a bad connection and retries.
  # Without the guard a retry closes a shift and opens another, turning one
  # four-hour shift into two — the hours stay roughly right while the shift
  # COUNT doubles, which is the shape that looks fine in a total and is wrong
  # in every per-shift figure.
  it "opens exactly one shift when the toggle is sent twice" do
    profile.set_availability!(true)

    expect { profile.set_availability!(true) }.not_to change { courier.courier_shifts.count }
    expect(courier.courier_shifts.open_now.count).to eq(1)
  end

  it "does nothing when they go off twice" do
    profile.set_availability!(true)
    profile.set_availability!(false)
    closed_at = courier.courier_shifts.last.ended_at

    travel_to 1.hour.from_now { profile.set_availability!(false) }

    expect(courier.courier_shifts.last.ended_at).to eq(closed_at),
                                                    "a second 'off' moved the end, so the shift length is wrong"
  end

  # An operator forcing a courier offline must close the shift too, or a
  # suspended courier counts as available capacity forever.
  it "closes the shift when an operator forces them offline" do
    profile.set_availability!(true)

    profile.set_availability!(false)

    expect(courier.courier_shifts.open_now).to be_empty
  end

  # An abandoned shift — the app was killed and the "off" never arrived —
  # is capped at now rather than left unbounded. Unbounded would inflate the
  # denominator and make utilisation look WORSE than it is, which is the
  # opposite bias to the one this table removes.
  it "counts a still-open shift up to now, not to infinity" do
    profile.set_availability!(true)

    travel_to 3.hours.from_now do
      expect(courier.courier_shifts.last.hours).to be_within(0.05).of(3.0)
    end
  end

  it "refuses a shift that ends before it starts" do
    shift = CourierShift.new(courier: courier, started_at: Time.current, ended_at: 1.hour.ago)

    expect(shift).not_to be_valid
  end

  # Zero-length is legal and meaningful: "they said available, we never saw
  # them". Different from no shift at all, and the row is the evidence they
  # tried.
  it "allows a shift that ends the instant it began" do
    at = Time.current
    shift = CourierShift.new(courier: courier, started_at: at, ended_at: at)

    expect(shift).to be_valid
  end

  # ── THE GATE ────────────────────────────────────────────────────────────
  #
  # A single entry point that nothing enforces is a convention, and the next
  # `update!(is_available:)` written in a hurry records the new state while
  # losing the fact that it changed. Same shape as the ledger gate, for the
  # same reason: the history cannot be reconstructed afterwards.
  describe "the single entry point" do
    # ── TWO SANCTIONED WRITERS, AND THE SECOND NEEDS ITS REASON ─────────────
    #
    # `CourierShift.close_abandoned!` writes the switch directly ON PURPOSE.
    # Going through the entry point would close the shift a SECOND time, at
    # `now`, overwriting the honest end — the moment the courier went quiet —
    # with the moment our sweep happened to run. It closes the shift itself, in
    # the same transaction, so switch and history still move together.
    SANCTIONED = [ "app/models/courier_profile.rb", "app/models/courier_shift.rb" ].freeze

    # A merchant's catalog item also has `is_available`, and it is unrelated —
    # matched by receiver so a catalog write is not mistaken for a courier one.
    NOT_A_COURIER = %w[item items @item catalog_item value values].freeze

    it "is the only thing that changes a courier's availability" do
      offenders = Dir[Rails.root.join("app/**/*.rb")].flat_map do |file|
        rel = file.sub(Rails.root.to_s + "/", "")
        next [] if SANCTIONED.include?(rel)

        File.readlines(file).each_with_index.filter_map do |line, i|
          next if line =~ /\A\s*#/
          # `&.` AS WELL AS `.` — the first version of this pattern missed safe
          # navigation entirely, and I found that by writing
          # `profile&.update_column(:is_available, false)` in this very feature
          # and watching the gate stay green. A gate that a common Ruby idiom
          # walks straight past is worse than none, because it certifies the
          # paths it cannot read.
          m = line.match(/([A-Za-z_][\w.@]*)&?\.(?:update!?|update_column|update_columns|update_all)\(\s*:?is_available\b/)
          next unless m
          next if NOT_A_COURIER.any? { |receiver| m[1].split(".").include?(receiver) }

          "#{rel}:#{i + 1} (#{m[1]})"
        end
      end

      expect(offenders).to be_empty,
                           "availability is written outside CourierProfile#set_availability! at: " \
                           "#{offenders.join(', ')}. That records the new state and loses the fact that it " \
                           "changed — and shift history cannot be reconstructed afterwards."
    end

    # Guards the guard: if the pattern stopped matching, the example above would
    # pass on an empty list while reading nothing.
    it "can still see an availability write" do
      seen = File.read(Rails.root.join("app/controllers/api/v1/merchants/catalog_items_controller.rb"))

      expect(seen).to match(/\.update!\(\s*is_available/),
                      "the catalog write this pattern is known to match is gone; re-check the pattern"
    end

    # The blind spot that let my own bypass through. Asserted directly so it
    # cannot come back by someone "simplifying" the regex.
    it "sees a write made with safe navigation" do
      pattern = /([A-Za-z_][\w.@]*)&?\.(?:update!?|update_column|update_columns|update_all)\(\s*:?is_available\b/

      expect("profile&.update_column(:is_available, false)").to match(pattern)
      expect("profile.update!(is_available: false)").to match(pattern)
    end
  end
end
