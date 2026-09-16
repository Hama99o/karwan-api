require "administrate/base_dashboard"

# A PIN AND A LANDMARK, never a street address. Afghan addresses are
# unreliable and people navigate by landmarks, so this is a coordinate, a
# sentence, a phone number — and, when it exists, a voice note, which is the
# form a customer who does not read fluently can actually give.
#
# Not routed: support fixes an address by phone with the customer, not by
# editing someone's home location behind their back.
class AddressDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    user: Field::BelongsTo,
    label: Field::String,
    landmark_note: Field::Text,
    phone: Field::String,
    latitude: Field::Number.with_options(decimals: 6),
    longitude: Field::Number.with_options(decimals: 6),
    has_voice_note: Field::Boolean,
    voice_note_seconds: Field::Number,
    is_default: Field::Boolean,
    deleted_at: Field::DateTime,
    created_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[label landmark_note phone is_default].freeze
  SHOW_PAGE_ATTRIBUTES = %i[
    user label landmark_note phone latitude longitude has_voice_note
    voice_note_seconds is_default deleted_at created_at
  ].freeze
  FORM_ATTRIBUTES = [].freeze

  def display_resource(address)
    address.label.presence || address.landmark_note.to_s.truncate(40)
  end
end
