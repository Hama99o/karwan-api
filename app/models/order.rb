class Order < ApplicationRecord
  include Monetary

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
  TRANSITIONS = {
    placed:    { accepted: %i[restaurant admin], rejected: %i[restaurant admin], cancelled: %i[customer admin] },
    accepted:  { preparing: %i[restaurant admin], cancelled: %i[restaurant admin] },
    preparing: { ready: %i[restaurant admin], cancelled: %i[restaurant admin] },
    ready:     { picked_up: %i[rider admin], cancelled: %i[admin] },
    picked_up: { delivered: %i[rider admin], failed: %i[rider admin] },
    delivered: {},
    rejected:  {},
    cancelled: {},
    failed:    {}
  }.freeze

  # Terminal states. `delivered` is the only happy one.
  TERMINAL = %i[delivered rejected cancelled failed].freeze

  # How long an order may sit in a state before it is a person waiting with
  # cold food. Every non-terminal state has one; a state with no timeout is how
  # an order is silently abandoned. Enforced by a job, not by this constant —
  # but the numbers live here so admin config can override them in one place.
  TIMEOUTS = {
    placed:    2.minutes,   # restaurant has not answered
    accepted:  45.minutes,  # accepted but never started
    preparing: 60.minutes,  # preparing forever
    ready:     20.minutes,  # sitting on the counter, no rider
    picked_up: 60.minutes   # in transit too long
  }.freeze

  enum :status, STATUSES
  # Explicit, never derived. "Has this money reached me?" is a WHERE clause.
  enum :cash_status, { pending: 0, collected: 1, settled: 2 }, prefix: :cash
  enum :payment_method, { cash: 0 }, prefix: :pay_by

  enum :rejection_reason,    { out_of_stock: 0, too_busy: 1, closing: 2, other: 3 }, prefix: :rejected_for
  enum :cancellation_reason, { customer_changed_mind: 0, restaurant_unavailable: 1,
                               no_rider_available: 2, duplicate: 3, other: 4 }, prefix: :cancelled_for
  enum :failure_reason,      { customer_refused: 0, nobody_home: 1, customer_unreachable: 2,
                               wrong_address: 3, other: 4 }, prefix: :failed_for
  enum :cancelled_by_role,   Roles::ALL, prefix: :cancelled_by

  belongs_to :customer,   class_name: User.name, inverse_of: :orders
  belongs_to :restaurant
  belongs_to :rider, class_name: User.name, optional: true, inverse_of: :deliveries

  has_many :order_items, dependent: :destroy
  has_many :transitions, class_name: OrderStatusTransition.name, dependent: :destroy,
           inverse_of: :order
  has_many :offers, class_name: OrderOffer.name, dependent: :destroy, inverse_of: :order
  has_many :wallet_entries, dependent: :nullify

  validates :code, presence: true, uniqueness: true
  validates :customer_phone, presence: true
  validates :delivery_latitude,  presence: true, numericality: { greater_than_or_equal_to: -90,  less_than_or_equal_to: 90 }
  validates :delivery_longitude, presence: true, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }
  validates :food_total, :delivery_fee, :commission, :rider_fee, :restaurant_payout,
            :customer_total, numericality: { greater_than_or_equal_to: 0 }
  validate  :totals_add_up

  before_validation :assign_code, on: :create

  scope :live,     -> { where.not(status: STATUSES.values_at(*TERMINAL)) }
  scope :newest_first, -> { order(created_at: :desc) }
  scope :for_rider, ->(rider) { where(rider: rider) }
  # The rider is holding our commission on every one of these.
  scope :cash_outstanding, -> { where(cash_status: %i[pending collected]) }

  def terminal?
    TERMINAL.include?(status.to_sym)
  end

  def allowed_transitions
    TRANSITIONS.fetch(status.to_sym, {})
  end

  def can_transition_to?(to_status, actor_role:)
    allowed_transitions[to_status.to_sym]&.include?(actor_role.to_sym) || false
  end

  # How long the order has been in its current state, and whether that is too
  # long. The admin board colours by this.
  def state_entered_at
    column = "#{status}_at"
    (respond_to?(column) ? public_send(column) : nil) || updated_at
  end

  def timeout_for_current_state
    TIMEOUTS[status.to_sym]
  end

  def overdue?
    timeout = timeout_for_current_state
    return false if timeout.blank?

    state_entered_at + timeout < Time.current
  end

  # What the rider hands the restaurant at pickup: the food, less our
  # commission. The rider funds this out of their own pocket, which is why the
  # refusal policy reimburses them the same day.
  def rider_advance
    restaurant_payout
  end

  # What the rider is left holding for us once the customer has paid and the
  # rider has kept their fee. This is our entire exposure per order.
  def platform_cash_held
    commission
  end

  private

  def assign_code
    self.code ||= loop do
      candidate = "D#{Time.current.strftime('%y%m%d')}#{SecureRandom.random_number(10_000).to_s.rjust(4, '0')}"
      break candidate unless self.class.exists?(code: candidate)
    end
  end

  # The parts must sum to the whole. This is the test that stops a discount, a
  # fee change or a rounding slip from producing an order whose total nobody
  # can explain at the door.
  def totals_add_up
    return if [ food_total, delivery_fee, customer_total ].any?(&:blank?)

    expected = food_total + delivery_fee
    return if (customer_total - expected).abs < 0.01

    errors.add(:customer_total, "must equal food_total + delivery_fee (#{expected})")
  end
end
