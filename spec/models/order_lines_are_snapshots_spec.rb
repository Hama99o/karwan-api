require "rails_helper"

# ── ONE-WAY DOOR 1 ─────────────────────────────────────────────────────────
#
# `CLAUDE.md`: *"Snapshot order lines. `order_items` stores the item name, price
# and chosen options AS THEY WERE at order time. Never join a historical order
# to live `menu_items` — a restaurant editing its menu would silently rewrite
# last month's orders."*
#
# It holds. `order_items` carries `name`, `unit_price`, `options_total`,
# `line_total` and `currency`; `order_item_options` carries `option_name`,
# `value_name`, `price_delta` and `currency`. The live `catalog_item_id` is kept
# too, and the customer serializer touches it for exactly one purpose — deciding
# whether to expose the id so the app can offer "order this again" — guarded by
# `kept?` so a discarded item stops being offered.
#
# **Nothing stopped the next person writing `item.catalog_item.name`.** The
# association is right there, `optional: true`, and reading through it would
# look like tidy de-duplication. The damage is silent and retroactive: a
# restaurant raising a price rewrites what every past customer was charged, in
# every receipt, dispute and report, with no error anywhere and nothing to
# compare against afterwards.
RSpec.describe "order lines are snapshots" do
  SNAPSHOT_COLUMNS = {
    "order_items" => %w[name unit_price options_total line_total currency],
    "order_item_options" => %w[option_name value_name price_delta currency]
  }.freeze

  # Where an ORDER is rendered or built. The catalog's own console pages
  # legitimately read live names — `catalog_item_option_dashboard` shows a live
  # option and must say what it is called now, not at some order's time.
  ORDER_CONTEXT = %w[
    app/serializers/customers/**/*.rb app/serializers/merchants/**/*.rb
    app/serializers/couriers/**/*.rb app/models/order*.rb
    app/services/orders/**/*.rb
  ].freeze

  it "stores the name, the price and the currency on the line itself" do
    SNAPSHOT_COLUMNS.each do |table, columns|
      actual = ActiveRecord::Base.connection.columns(table).map(&:name)

      expect(actual).to include(*columns),
                        "#{table} is missing #{(columns - actual).join(', ')} — without it the line has to ask " \
                        "the live catalog what it was called or cost, which is the one thing door 1 forbids."
    end
  end

  it "never reads a name or a price through the live catalog association" do
    offenders = Dir[*ORDER_CONTEXT.map { |g| Rails.root.join(g) }].flat_map do |file|
      File.readlines(file).each_with_index.filter_map do |line, i|
        next if line =~ /\A\s*#/
        next unless line =~ /catalog_item(_option_value)?s?&?\.\s*(name|price|price_delta|unit_price)/

        "#{file.sub(Rails.root.to_s + '/', '')}:#{i + 1}"
      end
    end

    expect(offenders).to be_empty,
                         "an order reads a name or price through the LIVE catalog at: #{offenders.join(', ')}. " \
                         "The snapshot on the order line is what the customer was charged; the catalog row is " \
                         "what the shop sells today. A restaurant editing its menu must not rewrite last " \
                         "month's orders, and nothing would report it if it did."
  end

  # Guards the guard: if the glob stopped matching, `offenders` would be empty
  # and the example above would pass while reading nothing.
  it "is actually reading the order-rendering code" do
    files = Dir[*ORDER_CONTEXT.map { |g| Rails.root.join(g) }]

    expect(files.size).to be > 5, "only #{files.size} files matched; the glob is not finding the serializers"
    expect(files.map { |f| File.basename(f) }).to include("order_serializer.rb")
  end

  # The behaviour the columns exist to produce, asserted end to end rather than
  # inferred from the schema: change the menu, and the old order must not move.
  it "does not follow the merchant's later price change" do
    order = create(:order, :with_items)
    item = order.order_items.first
    catalog_item = item.catalog_item
    skip "this factory builds no catalog link" if catalog_item.nil?

    was_name = item.name
    was_price = item.unit_price

    catalog_item.update!(name: "#{was_name} (renamed)", price: was_price + 500)

    expect(item.reload.name).to eq(was_name)
    expect(item.unit_price).to eq(was_price),
                               "the order line moved when the menu changed — the customer's receipt just changed " \
                               "retroactively"
  end
end
