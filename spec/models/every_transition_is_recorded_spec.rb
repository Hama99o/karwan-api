require "rails_helper"

# ── ONE-WAY DOOR 3 ─────────────────────────────────────────────────────────
#
# `CLAUDE.md`: *"A timestamp per state transition, not just the current
# `status`. 'How long do orders sit in preparing' is the metric that runs a
# delivery business and CANNOT BE BACKFILLED. Record the actor too."*
#
# `Dispatchable#transition_to!` does all three in one transaction: it sets
# `status`, sets the matching `<status>_at` column, and writes a
# `status_transitions` row carrying the actor and their role.
#
# **The failure this guards against is not a wrong timestamp — it is a missing
# row.** `order.update!(status: :ready)` is one line, looks harmless, works,
# and leaves no trace that the order was ever in `preparing` or for how long.
# Nothing errors, the order screen is correct, and the number that tells the
# owner whether his kitchens are slow is quietly wrong forever. There is no
# later query that can recover it.
RSpec.describe "every state transition is recorded" do
  # Models whose `status` is NOT a delivery lifecycle and so is not door 3's
  # business. Classified by the receiver in the source rather than by file, so
  # an order controller may still supersede an offer.
  NOT_A_LIFECYCLE = %w[offer offers user users merchant merchants admin_user].freeze

  SANCTIONED = "app/models/concerns/dispatchable.rb".freeze

  def status_writes
    Dir[Rails.root.join("app/**/*.rb")].flat_map do |file|
      rel = file.sub(Rails.root.to_s + "/", "")
      next [] if rel == SANCTIONED

      File.readlines(file).each_with_index.filter_map do |line, i|
        next if line =~ /\A\s*#/
        # `<receiver>.update!(status:` / `.update_all(status:` / `.update_column(:status`
        m = line.match(/([A-Za-z_][\w.\[\]]*)\.(?:update!?|update_all|update_column|update_columns)\(\s*:?status\b/)
        next unless m

        # THE WHOLE CHAIN, not its last segment. `order.offers.status_offered
        # .update_all(status: …)` ends in a SCOPE name, so taking the last part
        # classified an Offer write as an Order one — the receiver is the model
        # somewhere in the middle, and a scope can be named anything.
        chain = m[1].split(".")
        next if chain.any? { |part| NOT_A_LIFECYCLE.include?(part) }

        "#{rel}:#{i + 1} (chain: #{m[1]})"
      end
    end
  end

  it "writes an order's or trip's status only through transition_to!" do
    expect(status_writes).to be_empty,
                             "a lifecycle status is written outside Dispatchable#transition_to! at: " \
                             "#{status_writes.join(', ')}. That sets the status with no timestamp and no " \
                             "status_transitions row, so how long the order sat in that state is lost — and " \
                             "CLAUDE.md's door 3 says it cannot be backfilled."
  end

  # Guards the guard: if the pattern stopped matching, the example above would
  # pass on an empty list while reading nothing.
  it "can still see the status writes it is classifying" do
    all = Dir[Rails.root.join("app/**/*.rb")].flat_map do |file|
      File.readlines(file).grep(/\.(?:update!?|update_all|update_column)\(\s*:?status\b/)
    end

    expect(all.size).to be >= 5, "only #{all.size} status writes found; the pattern is not matching"
  end

  it "records the actor, their role and the moment, in one transaction" do
    courier = create(:user, :courier)
    order = create(:order, :with_items, :ready, courier: courier)

    expect { order.transition_to!(:picked_up, actor: courier, actor_role: :courier) }
      .to change { order.transitions.count }.by(1)

    row = order.transitions.order(:created_at).last
    expect(row.to_status).to eq("picked_up")
    expect(row.actor).to eq(courier)
    expect(row.actor_role).to eq("courier")
    expect(row.created_at).to be_present

    expect(order.reload.picked_up_at).to be_present,
                                         "the <status>_at column is what makes 'how long did this take' a query " \
                                         "rather than a join over transitions"
  end

  # The pairing is the point: a status without its row is the failure, so assert
  # they cannot come apart rather than that each exists.
  it "leaves no status change without a row" do
    courier = create(:user, :courier)
    order = create(:order, :with_items, :ready, courier: courier)

    before_status = order.status
    order.transition_to!(:picked_up, actor: courier, actor_role: :courier)

    recorded = order.transitions.pluck(:from_status, :to_status)
    expect(recorded).to include([ before_status, "picked_up" ]),
                        "the transition row must name what it moved FROM, or a gap in the chain is invisible"
  end
end
