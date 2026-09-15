# A pin, a landmark note, and a phone number. Deliberately NOT a street
# address: Afghan addresses are unreliable and people navigate by landmarks.
#
# Orders snapshot these fields rather than referencing an address, because the
# customer edits and deletes them and a past order must still say where it went.
class Address < ApplicationRecord
  include SoftDeletable
  belongs_to :user

  validates :latitude,  presence: true, numericality: { greater_than_or_equal_to: -90,  less_than_or_equal_to: 90 }
  validates :longitude, presence: true, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }

  scope :default_first, -> { order(is_default: :desc, created_at: :desc) }

  # One default per user. Done in a transaction so two concurrent saves cannot
  # both win and leave the user with two defaults.
  after_save :demote_other_defaults, if: -> { is_default? && saved_change_to_is_default? }

  private

  def demote_other_defaults
    user.addresses.where.not(id: id).where(is_default: true).update_all(is_default: false)
  end
end
