# A FOOD order. The other demand type is Trip.
#
# What the two share — the courier, the wallet, the commission, dispatch offers,
# the transition log, cash tracking — comes from Dispatchable. What is here is
# only what is actually about food: a restaurant, line items, a prep time, and a
# courier who advances money out of their own pocket at the counter.
class Order < ApplicationRecord
  include Monetary
  include Dispatchable

  # placed → accepted → preparing → ready → picked_up → delivered
  #   ↘ rejected   ↘ cancelled   ↘ failed
  STATUSES = {
    placed: 0, accepted: 1, preparing: 2, ready: 3, picked_up: 4, delivered: 5,
    rejected: 6, cancelled: 7, failed: 8
  }.freeze

  # Who may move the order, and where to. Anything not listed here is not a
  # transition — there is no "any state to any state" path, including for admin,
  # who instead gets explicit entries. An undeclared transition is how an order
  # ends up delivered without ever being picked up.
  #
  # Role names MUST be keys of Roles::ALL. They read `:restaurant` at first,
  # which is not a role, so `can_transition_to?` silently returned false and the
  # restaurant could not accept its own orders. The spec now asserts every role
  # and status named in this table is real, so it cannot drift again.
  TRANSITIONS = {
    placed:    { accepted: %i[restaurant_owner admin], rejected: %i[restaurant_owner admin], cancelled: %i[customer admin] },
    accepted:  { preparing: %i[restaurant_owner admin], cancelled: %i[restaurant_owner admin] },
    preparing: { ready: %i[restaurant_owner admin], cancelled: %i[restaurant_owner admin] },
    ready:     { picked_up: %i[courier admin], cancelled: %i[admin] },
    picked_up: { delivered: %i[courier admin], failed: %i[courier admin] },
    delivered: {},
    rejected:  {},
    cancelled: {},
    failed:    {}
  }.freeze

  # Terminal states. `delivered` is the only happy one.
  TERMINAL = %i[delivered rejected cancelled failed].freeze

  # How long an order may sit in a state before it is a person waiting with cold
  # food. Every non-terminal state has one; a state with no timeout is how an
  # order is silently abandoned. Enforced by a job, not by this constant — but
  # the numbers live here so admin config can override them in one place.
  TIMEOUTS = {
    placed:    2.minutes,   # restaurant has not answered
    accepted:  45.minutes,  # accepted but never started
    preparing: 60.minutes,  # preparing forever
    ready:     20.minutes,  # sitting on the counter, no courier
    picked_up: 60.minutes   # in transit too long
  }.freeze

  enum :status, STATUSES
  # Explicit, never derived. "Has this money reached me?" is a WHERE clause.
  # Payment-method-neutral: the same three states serve cash today and a digital
  # provider later, so there will not be two mechanisms disagreeing.
  enum :payment_status, { pending: 0, collected: 1, settled: 2 }, prefix: :payment
  enum :payment_method, { cash: 0 }, prefix: :pay_by

  enum :rejection_reason,    { out_of_stock: 0, too_busy: 1, closing: 2, other: 3 }, prefix: :rejected_for
  enum :cancellation_reason, { customer_changed_mind: 0, restaurant_unavailable: 1,
                               no_courier_available: 2, duplicate: 3, other: 4 }, prefix: :cancelled_for
  enum :failure_reason,      { customer_refused: 0, nobody_home: 1, customer_unreachable: 2,
                               wrong_address: 3, other: 4 }, prefix: :failed_for
  enum :cancelled_by_role,   Roles::ALL, prefix: :cancelled_by

  belongs_to :customer,   class_name: User.name, inverse_of: :orders
  belongs_to :restaurant
  # The UI calls this person the rider. The column is role-neutral because it is
  # the same human, and the same wallet, that carries passengers in the ride tab.
  belongs_to :courier, class_name: User.name, optional: true, inverse_of: :courier_orders

  has_many :order_items, dependent: :destroy

  validates :code, presence: true, uniqueness: true
  validates :customer_phone, presence: true
  validates :delivery_latitude,  presence: true, numericality: { greater_than_or_equal_to: -90,  less_than_or_equal_to: 90 }
  validates :delivery_longitude, presence: true, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }
  validates :food_total, :delivery_fee, :commission, :courier_fee, :restaurant_payout,
            :customer_total, numericality: { greater_than_or_equal_to: 0 }
  validate  :totals_add_up

  before_validation :assign_code, on: :create

  scope :for_restaurant, ->(restaurant) { where(restaurant: restaurant) }

  # What the courier hands the restaurant at pickup: the food, less our
  # commission. They fund this out of their own pocket, which is why the refusal
  # policy reimburses them the same day — losing 400 AFN through someone else's
  # behaviour is how we lose couriers, and they tell every other courier.
  def courier_advance
    restaurant_payout
  end

  # What the courier is left holding for us once the customer has paid and they
  # have kept their fee. This is our entire exposure per order.
  def platform_cash_held
    commission
  end

  private

  def assign_code
    self.code ||= loop do
      candidate = "K#{Time.current.strftime('%y%m%d')}#{SecureRandom.random_number(10_000).to_s.rjust(4, '0')}"
      break candidate unless self.class.exists?(code: candidate)
    end
  end

  # The parts must sum to the whole. This is the check that stops a discount, a
  # fee change or a rounding slip from producing an order whose total nobody can
  # explain at the door.
  def totals_add_up
    return if [ food_total, delivery_fee, customer_total ].any?(&:blank?)

    expected = food_total + delivery_fee
    return if (customer_total - expected).abs <= Monetary::ROUNDING_TOLERANCE

    errors.add(:customer_total, "must equal food_total + delivery_fee (#{expected})")
  end
end
