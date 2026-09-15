# A PASSENGER trip. The other demand type is Order.
#
# SCHEMA AND RULES ONLY — there is no trip UI, no fare calculator and no
# routing engine behind this yet, deliberately. It exists so that adding rides
# later is a calculator and some screens rather than a restructure of
# everything that references a job.
#
# The economic reason it exists at all: food demand is spiky, lunch and dinner,
# and the business turns on courier utilisation — roughly 13 jobs per person per
# day is where the fee pays them with no subsidy. A second demand stream on the
# same pool fills the idle hours.
class Trip < ApplicationRecord
  include Monetary
  include Dispatchable

  # The demand type is "ride", not "trip": `trips` is the table, `ride` is what
  # the customer buys and what a courier opts into. See CourierProfile::JOB_KINDS.
  JOB_KIND = "ride".freeze

  # requested → accepted → arrived → in_progress → completed
  #   ↘ cancelled   ↘ failed
  STATUSES = {
    requested: 0, accepted: 1, arrived: 2, in_progress: 3, completed: 4,
    cancelled: 5, failed: 6
  }.freeze

  # `arrived` is a state of its own rather than a timestamp on `accepted`
  # because it is the moment the passenger's wait ends and the courier's
  # waiting begins, and both sides argue about it.
  TRANSITIONS = {
    requested:   { accepted: %i[courier admin], cancelled: %i[customer admin] },
    accepted:    { arrived: %i[courier admin], cancelled: %i[customer courier admin] },
    arrived:     { in_progress: %i[courier admin], failed: %i[courier admin], cancelled: %i[admin] },
    in_progress: { completed: %i[courier admin], failed: %i[courier admin] },
    completed:   {},
    cancelled:   {},
    failed:      {}
  }.freeze

  TERMINAL = %i[completed cancelled failed].freeze

  TIMEOUTS = {
    requested:   2.minutes,   # nobody has accepted
    accepted:    15.minutes,  # accepted but never turned up
    arrived:     10.minutes,  # waiting at the pickup
    in_progress: 90.minutes   # in transit far too long
  }.freeze

  enum :status, STATUSES
  enum :payment_status, { pending: 0, collected: 1, settled: 2 }, prefix: :payment
  enum :payment_method, { cash: 0 }, prefix: :pay_by

  enum :cancellation_reason, { passenger_changed_mind: 0, courier_unavailable: 1,
                               no_courier_available: 2, duplicate: 3, other: 4 }, prefix: :cancelled_for
  enum :failure_reason,      { passenger_no_show: 0, passenger_unreachable: 1,
                               passenger_refused: 2, unsafe: 3, other: 4 }, prefix: :failed_for
  enum :cancelled_by_role,   Roles::ALL, prefix: :cancelled_by

  belongs_to :passenger, class_name: User.name, inverse_of: :trips
  # The UI calls this person the driver. Same human, same wallet, same
  # commission as the rider in the food tab.
  belongs_to :courier, class_name: User.name, optional: true, inverse_of: :courier_trips

  validates :code, presence: true, uniqueness: true
  validates :passenger_phone, presence: true
  validates :pickup_latitude,   presence: true, numericality: { greater_than_or_equal_to: -90,  less_than_or_equal_to: 90 }
  validates :pickup_longitude,  presence: true, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }
  validates :dropoff_latitude,  presence: true, numericality: { greater_than_or_equal_to: -90,  less_than_or_equal_to: 90 }
  validates :dropoff_longitude, presence: true, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }
  validates :fare, :commission, :courier_earnings, numericality: { greater_than_or_equal_to: 0 }
  validate  :fare_splits_correctly

  before_validation :assign_code, on: :create

  # Model A on a ride is the simpler half: the courier collects the fare, keeps
  # it, and owes us commission from their prepaid wallet. There is NO advance to
  # anybody — no merchant payout, nothing of ours in their pocket before the
  # job starts.
  def platform_cash_held
    commission
  end

  # Kept for symmetry with Order, where it is the merchant payout. On a ride
  # it is always zero, and saying so explicitly is cheaper than every caller
  # remembering which demand type advances money.
  def courier_advance
    0
  end

  # A ride advances nothing, so there is nothing for the wallet to float. The
  # only gate is that the wallet is not already blocked — which
  # CourierWallet#can_fund? checks separately for every job kind.
  #
  # This is the asymmetry in correction 7, and the reason there is deliberately
  # NOT one wallet check for both: a courier too short for a delivery can still
  # earn on a ride, and refusing them both would take income from the person
  # whose supply is already the scarce side.
  def wallet_requirement
    0
  end

  private

  def assign_code
    self.code ||= loop do
      candidate = "T#{Time.current.strftime('%y%m%d')}#{SecureRandom.random_number(10_000).to_s.rjust(4, '0')}"
      break candidate unless self.class.exists?(code: candidate)
    end
  end

  # The fare must split into exactly what the courier keeps plus what we take.
  # Same discipline as Order#totals_add_up: the parts sum to the whole, or the
  # record does not save.
  def fare_splits_correctly
    return if [ fare, commission, courier_earnings ].any?(&:blank?)
    return if (fare - (commission + courier_earnings)).abs <= Monetary::ROUNDING_TOLERANCE

    errors.add(:courier_earnings, "plus commission must equal the fare (#{fare})")
  end
end
