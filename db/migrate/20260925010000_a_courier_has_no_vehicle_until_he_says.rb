# F-92. `courier_profiles.vehicle_type` was NOT NULL DEFAULT 0, and 0 is
# `motorbike`. The app never sent the field (karwan-mobile `d6f313d` is the
# first build that asks), so every courier who registered from a phone was
# recorded as a motorbike, and dispatch believed it: a car driver was refused
# every car ride and every family ride, a bicycle courier got motorbike
# capacity. Every seed set the column directly, so no QA run ever saw it.
#
# From here a profile has NO vehicle until one is sent, and approval lists it
# as missing (`CourierProfile::REQUIRED_FOR_APPROVAL`).
#
# ── EXISTING 0s BECOME NULL, AND THAT WAS FREE ONLY BECAUSE OF THE DATE ──────
#
# A stored 0 cannot be told apart from a real "motorbike", so it is discarded
# rather than trusted. That is free because THERE IS NO PRODUCTION DATA as of
# 2026-09-25: Karwan is not deployed (no VPS, `KAMAL_HOST` blank), and every
# existing row is seed or QA data that is regenerated. Do NOT reuse this
# pattern after launch — against live couriers it would un-approve real people
# mid-shift. After launch the move is to keep the value and mark the row for a
# human to confirm.
#
# Irreversible on purpose: `down` cannot know which NULLs were motorbikes.
class ACourierHasNoVehicleUntilHeSays < ActiveRecord::Migration[8.1]
  def up
    change_column_default :courier_profiles, :vehicle_type, from: 0, to: nil
    change_column_null :courier_profiles, :vehicle_type, true
    execute "UPDATE courier_profiles SET vehicle_type = NULL WHERE vehicle_type = 0"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "which NULLs were motorbikes is not recorded"
  end
end
