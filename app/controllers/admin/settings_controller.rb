# The Config screen.
#
# Editable with no deploy is the whole point — Hamma9900 tunes prices by typing,
# and the pricing services read these rows on every quote. Only `value` is
# editable (see SettingDashboard): a mistyped key would create a row nothing
# reads, which `Setting.fetch` raises on rather than silently returning nil.
module Admin
  class SettingsController < Admin::ApplicationController
    def scoped_resource
      Setting.order(:key)
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
