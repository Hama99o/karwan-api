# The Config screen.
#
# Editable with no deploy is the whole point — Hamma9900 tunes prices by typing,
# and the pricing services read these rows on every quote. Only `value` is
# editable (see SettingDashboard): a mistyped key would create a row nothing
# reads, which `Setting.fetch` raises on rather than silently returning nil.
module Admin
  class SettingsController < Admin::ApplicationController
    # ── ONLY ROWS SOMETHING CAN READ ──────────────────────────────────────
    #
    # A row whose key is not in `Setting::DEFINITIONS` cannot be read at all —
    # `Setting.fetch` raises `KeyError` on an unknown key, deliberately, so a
    # silent nil never becomes a zero fee. Which means such a row is not merely
    # unused: it is **unreadable**, and listing it puts a number on the Config
    # screen that no code path could ever consult.
    #
    # Found on the rig: `delivery_fee` and `courier_fee`, left behind when the
    # single fee was replaced by the two-part tariff (`delivery_base_fee` +
    # `delivery_fee_per_km`, floored at `delivery_minimum_fee`). Both were
    # listed, both were editable, and both were the name Hamma9900 would look
    # for first. This file's own header says why that is the worst thing this
    # screen can do — *"editable with no deploy is the whole point"* — and
    # `setting.rb` records the same lesson about the price keys it had deleted.
    #
    # Scoped rather than only cleaned up, because a row deleted by a migration
    # today says nothing about the next key that is retired. The migration
    # removes the two; this makes the screen unable to show a third.
    #
    # THIS COVERS SHOW AND EDIT AS WELL, which is worth stating because it is
    # not obvious: Administrate's own `find_resource` is `scoped_resource.find`,
    # so an orphan is not merely hidden from the list — it is unreachable by
    # typing its id into the address bar. Checked in the gem rather than
    # assumed, and there is a request spec proving the 404.
    def scoped_resource
      Setting.where(key: Setting::DEFINITIONS.keys).order(:key)
    end

    # Every price change is logged. "Why did the delivery fee change last
    # Tuesday" is a question with an answer.
    def update
      setting = requested_resource
      before = setting.value

      if setting.update(value: params.require(:setting).permit(:value)[:value],
                        updated_by: nil)
        log_intervention("setting.changed", target: setting,
                                            before: { value: before }, after: { value: setting.value },
                                            details: { key: setting.key })
        redirect_to admin_setting_path(setting), notice: "#{setting.key} updated."
      else
        render :edit, status: :unprocessable_content
      end
    end
  end
end
