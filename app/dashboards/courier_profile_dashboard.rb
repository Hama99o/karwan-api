require "administrate/base_dashboard"

class CourierProfileDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    user: Field::BelongsTo,
    full_name: Field::String,
    father_name: Field::String,
    national_id_number: Field::String,
    verification_status: Field::Select.with_options(
      collection: ->(_f) { CourierProfile.verification_statuses.keys }
    ),
    vehicle_type: Field::Select.with_options(collection: ->(_f) { CourierProfile.vehicle_types.keys }),
    plate_number: Field::String,
    accepted_job_kinds: Field::String,
    is_available: Field::Boolean,
    guarantor_name: Field::String,
    guarantor_phone: Field::String,
    guarantor_relation: Field::String,
    work_area: Field::Text,
    last_latitude: Field::Number.with_options(decimals: 6),
    last_longitude: Field::Number.with_options(decimals: 6),
    location_updated_at: Field::DateTime,
    verified_at: Field::DateTime,
    # The documents the approval is MADE AGAINST. Until these were displayable
    # the console showed an operator a typed tazkira NUMBER and asked them to
    # approve the human it belonged to.
    id_document: AttachmentField,
    selfie: AttachmentField,
    vehicle_photo: AttachmentField,
    # WHO approved this person. It could only ever be nil before — the column
    # pointed at `users` and the console operator is an `AdminUser`.
    verified_by_admin_user: Field::BelongsTo.with_options(class_name: "AdminUser"),
    rejection_reason: Field::Text,
    created_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[full_name verification_status vehicle_type is_available
                             national_id_number guarantor_phone id_document selfie].freeze
  SHOW_PAGE_ATTRIBUTES = %i[
    user full_name father_name national_id_number verification_status vehicle_type
    plate_number accepted_job_kinds is_available guarantor_name guarantor_phone
    guarantor_relation work_area last_latitude last_longitude location_updated_at
    verified_at rejection_reason created_at id_document selfie vehicle_photo verified_by_admin_user
  ].freeze
  # Approval is a named action, not a dropdown — it must carry the approver's
  # identity, and a form edit would not.
  FORM_ATTRIBUTES = %i[
    full_name father_name national_id_number vehicle_type plate_number
    guarantor_name guarantor_phone guarantor_relation work_area
  ].freeze

  COLLECTION_FILTERS = {
    pending: ->(resources) { resources.verification_pending },
    approved: ->(resources) { resources.verification_approved },
    on_shift: ->(resources) { resources.available }
  }.freeze

  def display_resource(profile)
    profile.full_name.presence || profile.user&.display_name || "Courier ##{profile.id}"
  end
end
