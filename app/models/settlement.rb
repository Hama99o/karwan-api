# Expected AND counted, both stored, plus the named person who counted.
# Mismatches are normal — change floats, rounding, a note left with a customer.
# UNEXPLAINED mismatches are theft, and you cannot tell the two apart if only
# one number was ever written down.
class Settlement < ApplicationRecord
  include Monetary

  belongs_to :courier, class_name: User.name
  # Free text as well as an optional reference: the person counting cash in
  # Kabul may not have an account, and "who counted this" must never be null.
  belongs_to :counted_by, class_name: User.name, optional: true

  validates :expected_amount, :counted_amount, numericality: true
  validates :counted_by_name, presence: true
  validates :settled_at, presence: true

  scope :newest_first, -> { order(settled_at: :desc) }
  scope :mismatched,   -> { where.not("counted_amount = expected_amount") }

  def variance
    counted_amount - expected_amount
  end

  def balanced?
    variance.zero?
  end

  def short?
    variance.negative?
  end
end
