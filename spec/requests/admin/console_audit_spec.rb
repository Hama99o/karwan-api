require "rails_helper"

# EVERY CONSOLE EDIT LEAVES A TRACE, not only the dramatic ones.
#
# `log_intervention` was called by hand from the custom actions — approve,
# suspend, reassign, credit — so those were audited and Administrate's own
# create/update/destroy were not. That covered the buttons and missed the form,
# which is where the two most consequential edits in the system happen:
# `commission_rate` changes what a merchant is paid, and `owner_id` changes who
# controls a restaurant. Both are a plain save.
#
# One-way door #5: an audit row for every intervention, with actor, before and
# after. "Unanswerable later if nobody wrote it" is exactly what a missing row
# means — the merchant row shows the new commission, and nothing shows the old
# one or who typed it.
RSpec.describe "The console audits every edit", type: :request do
  let(:admin) { AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password") }
  let!(:merchant) { create(:merchant, name: "Kabab House", commission_rate: 0.125) }

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  def logs(action) = AuditLog.for_action(action).newest_first

  describe "a plain form save" do
    it "records the change, both sides of it, and who made it" do
      patch "/admin/merchants/#{merchant.id}", params: { merchant: { commission_rate: 0.2 } }

      log = logs("merchant.edited").first
      expect(log).to be_present
      expect(log.admin_user).to eq(admin)
      expect(log.target).to eq(merchant)
      expect(log.before["commission_rate"].to_f).to eq(0.125)
      expect(log.after["commission_rate"].to_f).to eq(0.2)
    end

    # WHO CONTROLS THIS RESTAURANT. The same save grants a role, so the audit
    # row is the only record of who handed it over.
    it "records an owner reassignment" do
      owner = create(:user, phone: "+93700000321")

      patch "/admin/merchants/#{merchant.id}", params: { merchant: { owner_id: owner.id } }

      log = logs("merchant.edited").first
      expect(log.before["owner_id"]).to be_nil
      expect(log.after["owner_id"]).to eq(owner.id)
    end

    it "says which screen it was typed on" do
      patch "/admin/merchants/#{merchant.id}", params: { merchant: { name: "Kabab House 2" } }

      expect(logs("merchant.edited").first.details).to include("via" => "console", "dashboard" => "merchants")
    end

    # A save that changed nothing is not an intervention. Without this the log
    # fills with rows that say nothing, and a log nobody reads is not a log.
    it "writes nothing when nothing changed" do
      expect { patch "/admin/merchants/#{merchant.id}", params: { merchant: { name: "Kabab House" } } }
        .not_to change(AuditLog, :count)
    end

    # A rejected form has not changed anything yet.
    it "writes nothing when the save was refused" do
      expect { patch "/admin/merchants/#{merchant.id}", params: { merchant: { name: "" } } }
        .not_to change(AuditLog, :count)

      expect(merchant.reload.name).to eq("Kabab House")
    end

    it "keeps the derived search blob out of the row" do
      patch "/admin/merchants/#{merchant.id}", params: { merchant: { name: "Kabab Palace" } }

      log = logs("merchant.edited").first
      expect(log.after.keys).to include("name")
      expect(log.after.keys).not_to include("search_text", "updated_at")
    end
  end

  describe "creating a record from the console" do
    it "records the whole row, because there is no before" do
      kind = create(:merchant_kind, slug: "bakery", name_en: "Bakery")

      expect {
        post "/admin/merchants", params: { merchant: {
          name: "Naan Shop", phone: "+93700000111", merchant_kind_id: kind.id, commission_rate: 0.1
        } }
      }.to change { logs("merchant.created").count }.by(1)

      log = logs("merchant.created").first
      expect(log.after["name"]).to eq("Naan Shop")
      expect(log.target).to eq(Merchant.find_by(name: "Naan Shop"))
      expect(log.admin_user).to eq(admin)
    end

    it "writes nothing when the create was refused" do
      expect { post "/admin/merchants", params: { merchant: { name: "" } } }
        .not_to change(AuditLog, :count)
    end
  end

  describe "deleting a record from the console" do
    # ── `merchant.discarded`, NOT `merchant.deleted` ────────────────────────
    #
    # `Admin::MerchantsController#destroy` now DISCARDS rather than destroys:
    # `Merchant` includes `SoftDeletable` and Administrate's generic action was
    # bypassing it, hard-deleting the shop and cascading onto its catalog
    # (docs/NOTES.md). So the audit row is written by that action rather than
    # by the generic `log_console_edit` hook, and it is named for what it does.
    #
    # It still carries the FULL before-snapshot. The row is no longer destroyed,
    # so that is belt and braces — but an audit entry is cheap and values it
    # never held cannot be added back later.
    it "records what the row held when it went" do
      doomed = create(:merchant, name: "Closing Down", phone: "+93700000222")

      expect { delete "/admin/merchants/#{doomed.id}" }
        .to change { logs("merchant.discarded").count }.by(1)

      log = logs("merchant.discarded").first
      expect(log.before["name"]).to eq("Closing Down")
      expect(log.before["phone"]).to eq("+93700000222")
    end

    # A merchant that has TRADED used to be refused outright, because a hard
    # delete would have orphaned its order history. A discard orphans nothing,
    # so it is now allowed — and audited. The `restrict_with_error` guard still
    # stands behind it for anything that does try to destroy.
    it "discards a merchant that has traded, and records that too" do
      create(:order, merchant: merchant)

      expect { delete "/admin/merchants/#{merchant.id}" }
        .to change { logs("merchant.discarded").count }.by(1)
      expect(merchant.reload).to be_discarded
    end
  end

  # The hook is on the base controller so a dashboard added later inherits it.
  # Asserted on a second dashboard, because "it works on merchants" and "it
  # works for every dashboard" are different claims.
  describe "every dashboard, not just the one it was written against" do
    it "audits a user edit too" do
      person = create(:user, name: "Old Name")

      patch "/admin/users/#{person.id}", params: { user: { name: "New Name" } }

      log = logs("user.edited").first
      expect(log.before["name"]).to eq("Old Name")
      expect(log.after["name"]).to eq("New Name")
    end

    # Settings keep their OWN action name and their own row, because
    # `Admin::SettingsController#update` does not call `super` — it logs
    # `setting.changed` with the key, which is more useful than a generic edit
    # ("why did the delivery fee change last Tuesday" is a question about a
    # key, not about a row id). Asserted here so the specialisation is
    # deliberate rather than a gap, and so nobody adds a second row later.
    it "leaves a setting change to its own, better log line" do
      setting = Setting.find_by(key: "delivery_base_fee") || create(:setting, key: "delivery_base_fee", value: "50")

      patch "/admin/settings/#{setting.id}", params: { setting: { value: "60" } }

      log = logs("setting.changed").first
      expect(log.before["value"]).to eq("50")
      expect(log.after["value"]).to eq("60")
      expect(log.details["key"]).to eq("delivery_base_fee")
      expect(logs("setting.edited")).to be_empty
    end
  end

  it "refuses the whole thing to a signed-out visitor" do
    delete "/admin/logout"

    expect { patch "/admin/merchants/#{merchant.id}", params: { merchant: { commission_rate: 0.9 } } }
      .not_to change(AuditLog, :count)
    expect(merchant.reload.commission_rate.to_f).to eq(0.125)
  end
end
