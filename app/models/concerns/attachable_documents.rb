# Validation for uploaded files, in one place.
#
# ── Why this is not left to Active Storage ────────────────────────────────
# `has_one_attached` validates NOTHING. It does not check the content type, it
# does not check the size, and it will happily store a 40 MB video where a
# tazkira photo belongs. docs/NOTES.md already records the sharper version of
# this trap: eight `has_one_attached` macros were declared here and Active
# Storage had never been installed, and every gate passed because the macro does
# not touch the database.
#
# ── The size limit is a cost decision, not a tidiness one ─────────────────
# CLAUDE.md correction 6: the per-order marginal cost must be effectively zero,
# and storage is on Hamma9900's own VPS with the disk already at 90%. A courier
# photographing their tazkira on a modern phone sends 4-8 MB without thinking
# about it; 5 MB is generous for a document that only has to be READABLE by a
# human in the admin console.
#
# It is also an upload the courier PAYS FOR in data (AFGHAN_UX.md §5), on a
# connection where a 40 MB upload simply never completes — so the limit is
# partly on their side.
module AttachableDocuments
  extend ActiveSupport::Concern

  # A photograph of a document or a person. JPEG and PNG only: HEIC arrives
  # from iPhones and nothing in the admin console can render it, and a PDF is
  # not a photo of a face.
  IMAGE_TYPES = %w[image/jpeg image/png].freeze
  MAX_IMAGE_BYTES = 5.megabytes

  # A held-to-record landmark note. AFGHAN_UX.md §2 makes this the answer to
  # low literacy — "the customer records where they live instead of writing
  # it" — so it must survive a bad connection, which means short and small.
  AUDIO_TYPES = %w[audio/mpeg audio/mp4 audio/aac audio/m4a audio/x-m4a audio/ogg].freeze
  MAX_AUDIO_BYTES = 2.megabytes

  class_methods do
    # Declares the validation for one or more attachments.
    #
    # `required: false` by default and deliberately: a courier's application is
    # built up over several submissions on a bad connection, and refusing the
    # whole form because one photo failed to upload is how an application is
    # abandoned. Completeness is checked at APPROVAL, by a human, which is
    # where it belongs.
    def validates_attached(*names, as: :image)
      types, max = as == :audio ? [ AUDIO_TYPES, MAX_AUDIO_BYTES ] : [ IMAGE_TYPES, MAX_IMAGE_BYTES ]

      validate do
        names.each do |name|
          file = public_send(name)
          next unless file.attached?

          unless types.include?(file.content_type)
            errors.add(name, "must be one of: #{types.join(', ')}")
          end

          errors.add(name, "must be smaller than #{max / 1.megabyte} MB") if file.byte_size > max
        end
      end
    end
  end
end
