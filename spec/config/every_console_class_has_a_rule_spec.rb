require "rails_helper"

# ═══ A CLASS IN THE HTML IS NOT A STYLE ON THE PAGE ═══════════════════════
#
# 24 Sept 2026: `karwan_admin.css` had never been registered, so the board's
# overdue rows — *"turns red... visible from across a room"* — computed a
# transparent background in a real browser, while `console_spec` stayed green
# asserting the class NAME was in the HTML. Checking for the gap's siblings
# then found six classes the views used that had no rule anywhere, including
# the reports page's `--warn` note (*"Do not use this alone to decide whether to
# recruit"*), which rendered as ordinary text.
#
# Two claims, each of which was false that day:
#
#   1. every stylesheet the repo ships is REGISTERED with the console, so a
#      rule written there reaches a browser at all;
#   2. every `karwan-*` class a console view uses has a RULE in one of them.
#
# The first is asserted against `Administrate::Engine.stylesheets` — the list
# the layout actually links — and `the_console_stylesheet_is_served_spec`
# follows the link over HTTP. Only our own `karwan-` prefix is checked:
# Administrate's classes are Administrate's.
RSpec.describe "every console class has a rule" do
  STYLESHEET_DIR = Rails.root.join("app/assets/stylesheets")

  let(:stylesheets) { Dir[STYLESHEET_DIR.join("*.css")].map { |p| File.basename(p, ".css") } }

  it "registers every stylesheet the repo ships" do
    expect(stylesheets).not_to be_empty
    unregistered = stylesheets - Administrate::Engine.stylesheets.map(&:to_s)

    expect(unregistered).to be_empty,
                            "#{unregistered.join(', ')} never reaches a browser — nothing links it. " \
                            "Register it in config/initializers/administrate.rb."
  end

  it "has a rule for every karwan- class a console view uses" do
    sources = Dir[Rails.root.join("app/{views,helpers,dashboards,fields}/**/*.{erb,rb}")]
    used = sources.flat_map { |path| File.read(path).scan(/\bkarwan-[a-z0-9_-]*[a-z0-9]/) }.uniq
    css = stylesheets.map { |name| STYLESHEET_DIR.join("#{name}.css").read }.join("\n")

    # The scan must be reading something, or an empty `used` passes vacuously.
    expect(used).to include("karwan-row--alert", "karwan-actions")
    unstyled = used.reject { |klass| css.match?(/\.#{Regexp.escape(klass)}(?![a-z0-9_-])/) }

    expect(unstyled).to be_empty,
                        "these classes are in the HTML with no rule in a registered stylesheet: " \
                        "#{unstyled.join(', ')}. A spec asserting the class name would still pass."
  end
end
