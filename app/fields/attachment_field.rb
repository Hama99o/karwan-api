# An Active Storage attachment, in the Administrate console.
#
# ── Why this is hand-written ──────────────────────────────────────────────
# Administrate 1.0 ships no ActiveStorage field: its types are BelongsTo,
# Boolean, Date, DateTime, Email, HasMany, HasOne, Number, Password,
# Polymorphic, RichText, Select, String, Text, Time, Url. There is a gem for
# it, and CLAUDE.md correction 14 says a third dependency comes to Hamma9901
# with its cost before any code — for three ERB partials and forty lines, it is
# not worth the ask.
#
# ── Why it is not optional ────────────────────────────────────────────────
# Eight attachments are declared across this schema — a courier's tazkira,
# selfie and vehicle photo, a merchant's logo, storefront and licence, a
# catalog item's photo, an address's landmark voice note — and until now
# NOTHING could display or accept a single one of them. So the console showed
# an operator a courier's typed tazkira NUMBER and asked them to approve the
# person, with the photograph of the document unviewable.
#
# That is the whole point of the approval: CLAUDE.md — "a courier advances our
# merchants' food out of their own pocket and carries our cash, so they need
# identity, a guarantor, documents, and a human approval with a name attached."
# An approval made without seeing the documents is a rubber stamp.
class AttachmentField < Administrate::Field::Base
  def attached?
    data.respond_to?(:attached?) && data.attached?
  end

  def filename
    data.filename.to_s if attached?
  end

  def byte_size
    data.byte_size if attached?
  end

  # Rendered inline as a picture where it IS one, because an operator checking
  # a face against a tazkira needs to see both at once, not download two files.
  def image?
    attached? && data.content_type.to_s.start_with?("image/")
  end

  def audio?
    attached? && data.content_type.to_s.start_with?("audio/")
  end

  def content_type
    data.content_type if attached?
  end
end
