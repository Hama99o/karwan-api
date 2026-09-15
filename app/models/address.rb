# A pin, a landmark note, and a phone number. Deliberately NOT a street
# address: Afghan addresses are unreliable and people navigate by landmarks.
#
# Orders snapshot these fields rather than referencing an address, because the
# customer edits and deletes them and a past order must still say where it went.
class Address < ApplicationRecord
  include AttachableDocuments
  include SoftDeletable

  # An address is a PIN, a VOICE NOTE and a PHONE NUMBER. The landmark text is
  # optional and secondary — see the migration for why. A voice note longer than
  # this is not a landmark, it is a monologue, and a courier will not listen to
  # it at a junction.
  MAX_VOICE_NOTE_SECONDS = 60
  belongs_to :user

  has_one_attached :voice_note
  # AUDIO, not an image — and a much tighter ceiling. A landmark note is "blue
  # gate near the park, second floor" spoken in ten seconds; anything measured
  # in megabytes is a recording that will not finish uploading on a Kabul
  # connection and will not be listened to by a courier in traffic.
  validates_attached :voice_note, as: :audio

  validates :voice_note_seconds, numericality: { greater_than: 0, less_than_or_equal_to: MAX_VOICE_NOTE_SECONDS },
                                 allow_nil: true
  validates :latitude,  presence: true, numericality: { greater_than_or_equal_to: -90,  less_than_or_equal_to: 90 }
  validates :longitude, presence: true, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }

  scope :default_first, -> { order(is_default: :desc, created_at: :desc) }
  scope :with_voice_note, -> { where(has_voice_note: true) }

  # Keeps the queryable flag honest, so a courier screen can show "there is a
  # voice note" without loading the blob — and cannot claim one that is not
  # attached.
  before_save :sync_voice_note_flag

  # Can a courier actually find this place? A pin alone is often not enough in
  # a city navigated by landmark, so an address needs the pin plus at least one
  # human description — spoken or written.
  def navigable?
    latitude.present? && longitude.present? &&
      (has_voice_note? || landmark_note.present?)
  end

  # One default per user. Done in a transaction so two concurrent saves cannot
  # both win and leave the user with two defaults.
  after_save :demote_other_defaults, if: -> { is_default? && saved_change_to_is_default? }

  private

  def sync_voice_note_flag
    self.has_voice_note = voice_note.attached?
    self.voice_note_seconds = nil unless has_voice_note?
    true
  end

  def demote_other_defaults
    user.addresses.where.not(id: id).where(is_default: true).update_all(is_default: false)
  end
end
