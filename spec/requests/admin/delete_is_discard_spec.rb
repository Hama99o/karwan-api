require "rails_helper"

# ═══ ONE-WAY DOOR 6: SOFT DELETE, NEVER HARD ═══════════════════════════════
#
# CLAUDE.md names four things — restaurants, riders, menu items and addresses —
# and the reason: *"a deleted record with live order history is a hole in the
# books."*
#
# The mechanism is built and correct. `SoftDeletable` gives `discard!`, and
# `Merchant#discard_dependents!` hides the catalog with the shop. **What was
# wrong was the button**: Administrate ships a `destroy` action that calls
# `destroy`, so the console bypassed the whole design and hard-deleted,
# cascading `dependent: :destroy` onto `catalog_categories` and
# `catalog_items`.
#
# Measured before the fix, by driving it: the merchant row was gone, **0**
# catalog items remained, and it answered 303 as though it had worked.
#
# The blast radius was bounded — `has_many :orders, dependent:
# :restrict_with_error` refused any merchant that had ever traded, so there was
# never a hole in the books. Bounded is not intended: the model said discard
# and the button said destroy. (That guard still stands behind `destroy`; what
# changed is that the button no longer calls it, so a traded merchant can now
# be DISCARDED, which orphans nothing.)
RSpec.describe "Delete in the console means discard", type: :request do
  let(:admin) do
    AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password")
  end

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  let(:merchant) { create(:merchant) }
  let!(:category) { create(:catalog_category, merchant: merchant) }
  let!(:item) { create(:catalog_item, merchant: merchant, catalog_category: category) }

  it "keeps the row, so order history still has something to point at" do
    delete "/admin/merchants/#{merchant.id}"

    expect(Merchant.unscoped.find_by(id: merchant.id)).to be_present
    expect(merchant.reload).to be_discarded
  end

  # The reason `discard_dependents!` exists: a shop that is gone must not leave
  # an orderable menu behind.
  it "hides the menu with the shop, rather than deleting it" do
    delete "/admin/merchants/#{merchant.id}"

    expect(CatalogItem.unscoped.find_by(id: item.id)).to be_present
    expect(item.reload).to be_discarded
    expect(category.reload).to be_discarded
  end

  # ── THE POSITIVE IS SHOWN FIRST, AND THAT IS THE POINT ──────────────────
  #
  # A negative assertion is only meaningful if the positive has been shown to
  # be possible. Asserting "it is absent from `Merchant.listed`" proves nothing
  # if `listed` is empty for some unrelated reason — a broken scope would pass
  # this exactly as a working discard does. That is the fifth shape wearing a
  # negation, and the first version of this example had it.
  it "takes it off the customer's list" do
    expect(Merchant.listed).to include(merchant), "not listed to begin with — the check below is vacuous"
    expect(CatalogItem.kept).to include(item), "not kept to begin with — the check below is vacuous"

    delete "/admin/merchants/#{merchant.id}"

    expect(Merchant.listed).not_to include(merchant)
    expect(CatalogItem.kept).not_to include(item)
  end

  # Door 5 applies to this as much as to the buttons: somebody removed a shop,
  # and who did it is not reconstructable later.
  it "records who removed it, and what went with it" do
    expect { delete "/admin/merchants/#{merchant.id}" }.to change(AuditLog, :count).by(1)

    log = AuditLog.newest_first.first
    expect(log.action).to eq("merchant.discarded")
    expect(log.admin_user_id).to eq(admin.id)
    expect(log.after["deleted_at"]).to be_present
  end

  # ── THE ONE THAT USED TO BE REFUSED, AND SHOULD NOT BE ───────────────────
  #
  # Hard delete was refused for a merchant that had traded, by
  # `has_many :orders, dependent: :restrict_with_error`, and rightly — it would
  # have orphaned order history. **A discard orphans nothing**: the row stays,
  # every past order still resolves through it, and the shop stops being
  # listed. That is what door 6 exists to allow, so discarding a traded
  # merchant is the improvement rather than a regression.
  #
  # MY FIRST VERSION OF THIS EXAMPLE WAS VACUOUS. It asserted
  # `Merchant.unscoped.find_by(id:)` is present and called that "still
  # refuses" — which a DISCARD satisfies just as well as a refusal, so it
  # could not tell the two apart and passed either way. Asserting the state,
  # not merely the row's existence, is what makes it a test.
  it "discards a merchant that has traded, and leaves its history resolvable" do
    traded = create(:merchant, latitude: 34.5553, longitude: 69.2075)
    order = create(:order, merchant: traded)

    expect(Merchant.listed).to include(traded), "not listed to begin with — the check below is vacuous"

    delete "/admin/merchants/#{traded.id}"

    expect(traded.reload).to be_discarded
    expect(Merchant.listed).not_to include(traded)
    expect(order.reload.merchant).to eq(traded)
  end

  # ── THE CASCADES THAT ARE LATENT RATHER THAN REACHABLE ──────────────────
  #
  # `User has_one :courier_wallet, dependent: :destroy` and `CourierWallet
  # has_many :wallet_entries, dependent: :destroy` would hard-delete a
  # courier's entire ledger — one-way door 4 inverted, since a balance can be
  # recomputed from entries and entries can never be reconstructed from a
  # balance.
  #
  # **It is now refused at the model AND unreachable from the console**, and
  # both halves are asserted: `wallet_entries` is `dependent:
  # :restrict_with_error`, so the cascade fails rather than runs; and no
  # `destroy` route exists for users, wallets, orders, entries or settlements,
  # so no button can start it. If somebody adds a route, these go red and the
  # cascade has to be dealt with first.
  describe "nothing holding money or history can be deleted at all" do
    # Driven, not inferred: the ledger survives both attempts.
    it "refuses to destroy a wallet that has entries, and the user with it" do
      courier = create(:user, :courier)
      wallet = courier.courier_wallet
      wallet.record_entry!(kind: :top_up, amount: 100)

      expect(wallet.destroy).to be(false)
      expect(courier.destroy).to be(false)
      expect(WalletEntry.where(courier_wallet_id: wallet.id).count).to eq(1)
    end

    # ── FROM THE ROUTES, NOT FROM A LIST ───────────────────────────────────
    #
    # The list below this block asserts that six named resources have no
    # destroy route. A list cannot see a resource nobody typed, and on
    # 24 Sept 2026 that is exactly where the bug was: driving EVERY destroy
    # route the console has found catalog items and catalog categories — both
    # built to be discarded, both "menu items" in door 6's own words —
    # hard-deleted by the generic action, an ordered item's line left pointing
    # at nothing. So every routed destroy is driven here, and must either
    # discard, or be a hard delete whose protection is named below.
    #
    # EACH PROTECTION IS A FACT ABOUT THE SCHEMA, CHECKED, not a sentence. "It
    # has no history" is a claim a migration can falsify without anyone
    # reading this file; the foreign keys that point at the table are what
    # actually decide whether a hard delete leaves a hole.
    references_to = lambda do |table|
      ActiveRecord::Base.connection.tables.flat_map do |from|
        ActiveRecord::Base.connection.foreign_keys(from).select { |fk| fk.to_table == table }
                          .map { |fk| [ from, fk.on_delete ] }
      end.sort_by(&:first)
    end

    HARD_DELETE_IS_SAFE = {
      # An ordered option is COPIED onto the order (option_name, value_name,
      # price_delta), and the order's pointer to the live value is nullified,
      # not left dangling and not blocking.
      "catalog_item_option_values" => lambda {
        expect(references_to.call("catalog_item_option_values")).to eq([ [ "order_item_options", :nullify ] ])
        expect(OrderItemOption.column_names).to include("option_name", "value_name", "price_delta")
      },
      # Referenced only by its own values. No order or money table points here.
      "catalog_item_options" => lambda {
        expect(references_to.call("catalog_item_options")).to eq([ [ "catalog_item_option_values", nil ] ])
      },
      # The cuisine taxonomy, referenced only by the shop-to-cuisine links.
      "merchant_categories" => lambda {
        expect(references_to.call("merchant_categories")).to eq([ [ "merchant_category_assignments", nil ] ])
      },
      # Nothing points at an opening-hours row.
      "merchant_opening_hours" => lambda {
        expect(references_to.call("merchant_opening_hours")).to be_empty
      }
    }.freeze

    routed_destroys = Rails.application.routes.routes.filter_map { |route|
      controller = route.defaults[:controller].to_s
      next unless controller.start_with?("admin/") && route.defaults[:action] == "destroy"
      next if controller == "admin/sessions"

      controller.delete_prefix("admin/")
    }.uniq

    it "found the console's destroy routes, so an empty table cannot pass" do
      expect(routed_destroys.size).to be >= 7
    end

    it "names a protection only for a destroy that is routed and really hard-deletes" do
      expect(HARD_DELETE_IS_SAFE.keys - routed_destroys).to be_empty
    end

    routed_destroys.each do |resource|
      it "admin/#{resource}#destroy keeps history: it discards, or its protection holds" do
        model = Administrate::ResourceResolver.new("admin/#{resource}").resource_class
        record = create(model.model_name.singular.to_sym)

        delete "/admin/#{resource}/#{record.id}"
        row = model.unscoped.find_by(id: record.id)

        if model.method_defined?(:discard!)
          expect(row).to be_present, "#{resource} can be discarded and was HARD-deleted"
          expect(row.deleted_at).to be_present
          expect(HARD_DELETE_IS_SAFE).not_to have_key(resource.to_s),
                                         "#{resource} discards now — take it off HARD_DELETE_IS_SAFE"
        else
          protection = HARD_DELETE_IS_SAFE[resource.to_s]
          expect(protection).to be_present,
                                "#{resource} is hard-deleted from the console and nothing says why that is safe"
          instance_exec(&protection)
        end
      end
    end

    # THE UNDO. A delete that is recoverable only by a developer is not
    # recoverable by the person who made the mistake — and one that feels safe
    # gets clicked more readily than one that is final.
    %w[catalog_items catalog_categories].each do |resource|
      it "restores a deleted #{resource.singularize.humanize.downcase} from its page" do
        model = Administrate::ResourceResolver.new("admin/#{resource}").resource_class
        record = create(model.model_name.singular.to_sym)
        delete "/admin/#{resource}/#{record.id}"

        get "/admin/#{resource}/#{record.id}"
        expect(response.body).to include("/admin/#{resource}/#{record.id}/restore")

        expect { patch "/admin/#{resource}/#{record.id}/restore" }
          .to change { model.unscoped.find(record.id).deleted_at }.to(nil)
      end
    end

    %w[users courier_wallets orders wallet_entries settlements audit_logs].each do |resource|
      it "has no destroy route for #{resource}" do
        routed = Rails.application.routes.routes.any? do |route|
          route.defaults[:controller] == "admin/#{resource}" && route.defaults[:action] == "destroy"
        end

        expect(routed).to be(false),
                          "admin/#{resource} has a destroy route — check what it cascades onto first"
      end
    end
  end
end
