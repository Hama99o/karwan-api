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

  it "takes it off the customer's list" do
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
