# A THEME IS A PREFERENCE OF A PERSON, NOT A SETTING OF A HANDSET.
#
# The same argument that put `locale` on the user: AFGHAN_UX.md §7 — phones are
# SHARED here. A father and a son on one handset are two people with two
# languages and two eyes, and a preference stored on the device gives the second
# one the first one's choice.
#
# The mobile store already says so, and had removed its own `updateMe` call
# rather than stub it: "There is no API yet, and when there is, the theme
# belongs on the user for the same reason the language does." Marked as an
# absence rather than faked, which is why this arrives as a request instead of
# a surprise.
#
# `system` is the default and the honest one — a phone in Kabul sunlight and the
# same phone at night are different legibility problems, and the OS already
# knows which it is in.
class AddPreferredThemeToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :preferred_theme, :string, null: false, default: "system"
  end
end
