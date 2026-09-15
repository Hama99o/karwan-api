class AddVoiceNoteSupportToAddresses < ActiveRecord::Migration[8.1]
  # THE HIGHEST-VALUE FEATURE IN THE APP FOR THIS MARKET, and it is not obvious.
  #
  # A large share of Afghan adults cannot read or write fluently, and the share
  # is lower again for women and rural users. Typing "the blue gate near the
  # mosque, second floor" in Pashto is the single hardest action in the whole
  # order flow. SAYING it is trivial — and a courier who can hear it needs
  # nothing else.
  #
  # So an address is a PIN, a VOICE NOTE, and a PHONE NUMBER. The text field
  # stays, but it is optional and secondary, not the mechanism.
  #
  # The audio itself is an Active Storage attachment (`has_one_attached
  # :voice_note`). What lives here is only what a query needs to know without
  # loading the blob: whether there is one at all, and how long it is, so a
  # client can render a player and a courier screen can show a duration before
  # fetching anything.
  def change
    change_table :addresses, bulk: true do |t|
      t.boolean :has_voice_note, null: false, default: false
      t.integer :voice_note_seconds
    end

    add_index :addresses, :has_voice_note, where: "has_voice_note = TRUE",
                                           name: "index_addresses_with_voice_notes"
  end
end
