# Append-only. Who moved this order, from what, to what, when, and why.
#
# A nil actor means the system did it — i.e. a timeout fired. That distinction
# is the difference between "the restaurant rejected it" and "the restaurant
# never answered", and support needs to know which.
class OrderStatusTransition < ApplicationRecord
  enum :from_status, Order::STATUSES, prefix: :from
  enum :to_status,   Order::STATUSES, prefix: :to
  enum :actor_role,  Roles::ALL, prefix: :by

  belongs_to :order, inverse_of: :transitions
  belongs_to :actor, class_name: User.name, optional: true

  validates :to_status, presence: true

  scope :chronological, -> { order(:created_at) }

  def system?
    actor_id.nil?
  end
end
