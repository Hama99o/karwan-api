module Couriers
  # A courier's APPLICATION, as the applicant sees it.
  #
  # Three things it must answer, because between submitting and being approved a
  # courier can do nothing at all and will otherwise conclude the app is broken:
  #   • where am I — pending, approved, rejected
  #   • what do I still owe
  #   • if I was rejected, why, and can I fix it
  #
  # `missing` is a list of FIELD NAMES, never prose. The server cannot write
  # Pashto (the same rule as the job step list's `label_key`), so the app
  # renders its own copy per field.
  class RegistrationSerializer < ApplicationSerializer
    identifier :id

    fields :verification_status, :full_name, :father_name, :national_id_number,
           :guarantor_name, :guarantor_phone, :guarantor_relation, :work_area,
           :plate_number, :vehicle_type, :accepted_job_kinds, :verified_at

    # Why they were turned down. Written by a human in the admin console, so it
    # is the one field here that is prose — and it is shown as given, because a
    # courier who cannot see the reason cannot fix it.
    field :rejection_reason

    field :missing do |profile|
      profile.missing_for_approval
    end

    field :ready_for_approval do |profile|
      profile.ready_for_approval?
    end

    # Which documents have landed. Not URLs: the applicant has no reason to
    # re-download their own tazkira, and signing eight URLs per request costs
    # more than it answers.
    field :documents do |profile|
      {
        id_document: profile.id_document.attached?,
        selfie: profile.selfie.attached?,
        vehicle_photo: profile.vehicle_photo.attached?
      }
    end

    # Whether they can actually start. Approval alone is not enough — a courier
    # needs the ROLE to switch into the courier tab and a WALLET to be charged
    # commission, and both are granted at approval.
    field :can_start do |profile|
      profile.verification_approved? &&
        profile.user&.role?(:courier) &&
        profile.user&.courier_wallet.present?
    end
  end
end
