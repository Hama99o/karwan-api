# THE SPOKEN HALF OF THE ADDRESS, SNAPSHOT LIKE THE REST OF IT.
#
# R12: a large share of Afghan adults cannot read fluently, so an address is *a
# pin, a voice note, and a phone number*, with the text field optional rather
# than primary — typing "the blue gate near the mosque, second floor" in Pashto
# is the hardest single action in the order flow and saying it is trivial.
#
# `addresses` has carried `has_voice_note`, `voice_note_seconds` and the
# attachment since that was built, and the customer's app can play it. **The
# order never copied it**, so the one person who needs it — the courier standing
# at a junction — was never given it. `Couriers::JobSteps` even sends
# `has_voice_note: false` as a literal.
#
# ── WHY A COLUMN AND NOT A REFERENCE TO THE ADDRESS ───────────────────────
#
# `Orders::PlaceService` already says it: *"The address is COPIED, not
# referenced. The customer edits and deletes their saved pins, and a past order
# must still say where it actually went."* The voice note is part of the
# address; it was simply the part left behind.
#
# `voice_note_seconds` is a column rather than a read of the blob so the board,
# the step list and any report can ask "is there one, and how long" without
# loading audio — the same reason `addresses` has it.
class AddDeliveryVoiceNoteToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :delivery_voice_note_seconds, :integer
  end
end
