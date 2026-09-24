# ── THE CONSOLE'S OWN STYLESHEET, WHICH NOTHING HAD EVER LOADED ─────────────
#
# `app/assets/stylesheets/karwan_admin.css` carries the board's staleness
# colours — *"an order sitting in one state too long turns red... visible from
# across a room"* — the dashboard tiles, and the interventions panel. It was
# never registered, so none of it reached a browser. Measured on the dev board:
# 50 `karwan-row--alert` rows, computed background `rgba(0, 0, 0, 0)`.
# `console_spec` asserted the CLASS NAME in the HTML, which is true whether or
# not any rule for it is loaded.
#
# Administrate links every registered stylesheet from its layout
# (`Administrate::Engine.stylesheets`), which is how hatiwal-api's console is
# styled too.
Rails.application.config.to_prepare do
  Administrate::Engine.add_stylesheet("karwan_admin") unless Administrate::Engine.stylesheets.include?("karwan_admin")
end
