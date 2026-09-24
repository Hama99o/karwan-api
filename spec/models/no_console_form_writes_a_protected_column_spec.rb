require "rails_helper"

# ═══ THE OPS CONSOLE IS A WRITE SURFACE THE OTHER GATES CANNOT SEE ═════════
#
# Administrate builds its permitted parameters from a dashboard's
# `FORM_ATTRIBUTES` and calls `update` generically. So a column becomes
# operator-writable by **adding one symbol to an array** — there is no
# assignment anywhere for a source-scanning gate to find.
#
# MEASURED. With `:balance` added to `CourierWalletDashboard::FORM_ATTRIBUTES`,
# `money_moves_only_through_the_ledger_spec` passed, and so did all 1,021
# examples in `spec/requests/admin` and `spec/models`. An operator could then
# type a new balance into a form and move money with no ledger row —
# `spec/requests/admin/balance_moves_only_through_the_ledger_spec.rb` is that
# consequence, proven by planting it.
#
# ── WHY A LIST OF COLUMNS RATHER THAN A CLEVER RULE ──────────────────────
#
# "Which columns are protected" is a product judgement, not something derivable
# from the schema: `credit_line` sits on the same form as `balance` and IS
# meant to be typed — it is a permission to go negative, not money that has
# moved. Naming each column with the reason is the same shape as the
# `NOT_MONEY` list in the currency gate, and it makes the next addition an
# argument somebody has to make rather than a symbol nobody notices.
RSpec.describe "no console form writes a protected column" do
  # Columns that may only change through the code path that records WHY.
  # Model, column, and the door it belongs to.
  let(:protected_columns) do
    {
      "CourierWallet" => {
        "balance" => "one-way door 4 — only CourierWallet#record_entry!, which writes the ledger row " \
                     "in the same transaction. A balance typed into a form is a hole in the books."
      },
      "Order" => {
        "status" => "one-way door 3 — only transition_to!, which records the actor and the timestamp. " \
                    "A status overwritten in place cannot say who moved it or when.",
        "commission" => "frozen at quote time (correction 13). Editing it rewrites what a merchant is owed " \
                        "for an order that already happened.",
        "merchant_payout" => "same; it is what the courier advanced in cash.",
        "customer_total" => "same; it is what the customer was told to bring."
      },
      "Trip" => {
        "status" => "one-way door 3, as Order above.",
        "fare" => "quoted upfront and frozen on the trip, never metered (correction 13)."
      },
      "WalletEntry" => {
        "amount" => "one-way door 4 — an editable ledger entry is not a ledger.",
        "kind" => "same."
      },
      "Settlement" => {
        "expected_amount" => "expected AND counted are both stored so a variance can be argued with. " \
                             "Editing either makes the settlement unauditable.",
        "counted_amount" => "same."
      },
      "MerchantStatement" => {
        "net_received" => "a statement is a financial record already shown to a partner; editing one " \
                          "rewrites what they were told."
      },
      "AuditLog" => {
        "action" => "one-way door 5 — an editable audit log is not an audit log.",
        "actor_id" => "same."
      }
    }
  end

  # Every dashboard, found rather than listed, so a new one is covered the day
  # it is written.
  let(:dashboards) do
    Dir[Rails.root.join("app/dashboards/*_dashboard.rb")].map do |path|
      File.basename(path, ".rb").camelize.constantize
    end
  end

  it "finds the dashboards at all" do
    expect(dashboards.size).to be >= 20, "the dashboard sweep found almost nothing — every check below is vacuous"
    expect(dashboards).to include(CourierWalletDashboard, OrderDashboard)
  end

  it "exposes no protected column in any form" do
    offences = dashboards.flat_map do |dashboard|
      model = dashboard.name.sub(/Dashboard\z/, "")
      guarded = protected_columns[model] || {}
      next [] if guarded.empty?

      form = dashboard.const_defined?(:FORM_ATTRIBUTES) ? dashboard::FORM_ATTRIBUTES.map(&:to_s) : []
      (form & guarded.keys).map { |column| "#{dashboard.name} lets an operator type #{column} — #{guarded[column]}" }
    end

    expect(offences).to be_empty, offences.join("\n")
  end

  # ── AND FROM THE OTHER SIDE: EVERY COLUMN A FORM CAN WRITE, ARGUED FOR ───
  #
  # Audited 2026-09-24. The list above names what is PROTECTED, so a money
  # column nobody thought to list — `delivery_fee`, `courier_fee`,
  # `commission_topup`, `payment_status`, `merchant_paid_at`, a ledger row's
  # `balance_after` — would become typeable by adding one symbol to a
  # FORM_ATTRIBUTES array, and this file would stay green. A list of what is
  # guarded cannot see what nobody guarded.
  #
  # So the writable side is enumerated too, from the dashboards themselves: a
  # column any console form can type must appear here with the reason typing it
  # is legitimate. A new one fails until somebody makes that argument; a listed
  # one that stops being writable fails until it is removed.
  let(:meant_to_be_typed) do
    {
      "CatalogCategory" => [ %w[merchant name position], "a live menu, not history — orders snapshot their lines" ],
      "CatalogItem" => [ %w[merchant catalog_category name description price photo is_available prep_time_minutes position size_class],
                         "a live menu; an order copies name, price and options at the moment it is placed (door 1)" ],
      "CatalogItemOption" => [ %w[catalog_item name selection_type required min_selections max_selections position], "a live menu" ],
      "CatalogItemOptionValue" => [ %w[catalog_item_option name price_delta is_available position],
                                    "a live menu; ordered options are copied onto order_item_options" ],
      "CourierProfile" => [ %w[full_name father_name national_id_number vehicle_type plate_number guarantor_name guarantor_phone guarantor_relation work_area],
                            "an application an operator corrects on the phone; approval stays a named intervention" ],
      "CourierWallet" => [ %w[credit_line], "a permission to go negative, not money that has moved (see above)" ],
      "MerchantCategory" => [ %w[slug name_ps name_fa name_en position is_active], "the cuisine taxonomy" ],
      "Merchant" => [ %w[name merchant_kind phone status prep_time_minutes commission_rate latitude longitude landmark_note owner owner_name
                         owner_phone owner_national_id_number license_number contact_person_name contact_person_phone logo storefront_photo
                         license_photo merchant_categories],
                      "a shop's profile. commission_rate applies to the NEXT order, never to one placed; every edit is audited with before and after" ],
      "MerchantKind" => [ %w[slug name_ps name_fa name_en position is_active], "a taxonomy" ],
      "MerchantOpeningHour" => [ %w[merchant day_of_week opens_at closes_at], "a schedule" ],
      "PricingRate" => [ %w[base per_km per_minute minimum is_selectable position], "tariffs he retunes without a deploy (correction 13); quotes freeze what they used" ],
      "Setting" => [ %w[value], "the settings are there to be tuned; key, type and description are ours" ],
      "User" => [ %w[name locale status], "status is read on every request (account_active?), so a form edit takes effect like the intervention" ]
    }
  end

  it "lets a form write only columns somebody has argued may be typed" do
    writable = dashboards.each_with_object({}) do |dashboard, found|
      form = dashboard.const_defined?(:FORM_ATTRIBUTES) ? Array(dashboard::FORM_ATTRIBUTES).map(&:to_s) : []
      found[dashboard.name.delete_suffix("Dashboard")] = form if form.any?
    end

    unargued = writable.flat_map do |model, columns|
      (columns - Array(meant_to_be_typed.dig(model, 0))).map { |c| "#{model}##{c}" }
    end
    stale = meant_to_be_typed.flat_map do |model, (columns, _)|
      (columns - Array(writable[model])).map { |c| "#{model}##{c}" }
    end

    expect(unargued).to be_empty, "a console form can type #{unargued.join(', ')} and nothing says why that is safe"
    expect(stale).to be_empty, "listed as typeable but no form writes it any more: #{stale.join(', ')}"
  end

  # So the list cannot quietly stop describing the schema — a protected column
  # that has been renamed protects nothing and reads as if it does.
  it "names only columns that exist" do
    missing = protected_columns.flat_map do |model_name, columns|
      model = model_name.constantize
      (columns.keys - model.column_names).map { |column| "#{model_name} has no column #{column}" }
    end

    expect(missing).to be_empty, missing.join("\n")
    expect(protected_columns.values.flat_map(&:values)).to all(be_present)
  end

  # ── HOW MUCH OF THIS GATE IS LIVE TODAY, MEASURED AND NOT ASSUMED ────────
  #
  # Only `CourierWalletDashboard` of the protected models has a form at all —
  # the other six are `only: %i[index show]` in `routes.rb`, which says of them
  # *"an editable audit log is not an audit log, and a ledger whose entries can
  # be rewritten cannot be reconciled."* That convention was held by the routes
  # file and by nothing else.
  #
  # So one entry is guarding a live form and six are guarding the day somebody
  # gives those resources one. Both are worth having and they are NOT the same
  # strength, which is why this says which is which out loud rather than
  # letting the list look uniformly enforced.
  it "says which protected models have a form today" do
    with_form = protected_columns.keys.select do |model|
      dashboard = "#{model}Dashboard".constantize
      dashboard.const_defined?(:FORM_ATTRIBUTES) && dashboard::FORM_ATTRIBUTES.any?
    end

    expect(with_form).to eq(%w[CourierWallet]),
                         "the set of protected models with an editable console form has changed to " \
                         "#{with_form.join(', ')}. That is not automatically wrong — but a resource " \
                         "routes.rb calls read-only has just become writable, so check the new form " \
                         "against the columns above and update this expectation deliberately."
  end

  # ── THE GATE CAN GO RED ──────────────────────────────────────────────────
  #
  # Run against a form that DOES expose a protected column, so this cannot join
  # the list of checks that pass because they look at nothing.
  it "reports a form that exposes a protected column" do
    guarded = { "balance" => "the ledger's" }
    form = %w[credit_line balance]

    expect(form & guarded.keys).to eq(%w[balance])
    expect(%w[credit_line] & guarded.keys).to be_empty
  end
end
