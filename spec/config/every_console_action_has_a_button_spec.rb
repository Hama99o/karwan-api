require "rails_helper"

# ═══ A CONSOLE ACTION NOBODY CAN PRESS IS NOT AN ACTION ═══════════════════
#
# 24 Sept 2026: twenty console interventions — reassign, settle, approve,
# revoke sessions and the rest — were routes with NO FORM on any page. Every
# request spec drove them by URL, so all were green and none was usable by an
# operator at a laptop. `every_intervention_can_be_pressed_spec` now presses
# each of those twenty through its rendered form.
#
# That file only knows the twenty that existed. THIS is for the next one: every
# custom member action under `/admin` (anything that is not Administrate's own
# index/show/new/create/edit/update/destroy) must have its path helper used by
# some console template — or be named below with the reason it has no button.
RSpec.describe "every console action has a button" do
  CRUD = %w[index show new create edit update destroy].freeze

  # Actions that are deliberately not buttons. Empty today; a reason is
  # required for each, because "added the route and forgot the form" is
  # exactly what this file exists to catch.
  NO_BUTTON = {}.freeze

  let(:custom_actions) do
    Rails.application.routes.routes.filter_map do |route|
      controller = route.defaults[:controller].to_s
      action = route.defaults[:action].to_s
      next unless controller.start_with?("admin/") && route.name.present?
      next if CRUD.include?(action) || controller == "admin/sessions"

      "#{route.name}_path"
    end.uniq
  end

  let(:templates) { Dir[Rails.root.join("app/views/admin/**/*.erb")].map { |path| File.read(path) }.join("\n") }

  it "is reading the console's routes, not an empty list" do
    expect(custom_actions).to include("reassign_admin_order_path", "settle_admin_courier_wallet_path")
  end

  it "renders a button or form for every custom console action" do
    unpressable = custom_actions.reject { |helper| templates.include?(helper) } - NO_BUTTON.keys

    expect(unpressable).to be_empty,
                           "these console actions are routes no page renders: #{unpressable.join(', ')}. " \
                           "A request spec driving the URL passes either way — put a form on the record's " \
                           "page (and a press in every_intervention_can_be_pressed_spec), or name it in " \
                           "NO_BUTTON with the reason."
  end
end
