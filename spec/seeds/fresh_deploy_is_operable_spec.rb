require "rails_helper"

# ═══ A FRESH DEPLOY IS OPERABLE BY ONE PERSON ON DAY ONE ═══════════════════
#
# Building and booting the production image for the first time on 2026-09-17
# found three things, **one at a time, and two of them by coming back for
# something else**:
#
#   · no compiled assets — the ops console would have rendered unstyled
#   · the whole test toolchain shipped in the image
#   · **no `AdminUser` at all** — nobody could open the console
#
# A fourth will exist. So this stops hunting them individually and encodes the
# property instead:
#
#   After production seeding on an empty database, the platform is operable by
#   one person on day one — and contains nothing fake.
#
# ── WHY THE NEGATIVE HALF IS DERIVED ─────────────────────────────────────
#
# "No sample data" is asserted over **every model that is not reference or
# config**, taken from `ApplicationRecord.descendants`, rather than over four
# named tables. A fifth sample-bearing table added later is covered without
# anybody remembering this file — the same reason `ROUTED` is asked of the
# router and the ENV gate scans the source.
RSpec.describe "a fresh production deploy" do
  # Rows that SHOULD exist after a production seed: configuration Hamma9900
  # tunes, the taxonomy the app cannot run without, and the account that opens
  # the console.
  REFERENCE_MODELS = [ Setting, PricingRate, MerchantKind, MerchantCategory, AdminUser ].freeze

  # ── STUB THE PREDICATE, NOT THE ENVIRONMENT ──────────────────────────────
  #
  # Replacing `Rails.env` wholesale also changes which `database.yml` entry
  # ActiveRecord resolves, so the first version of this spec tried to connect
  # to the PRODUCTION database and failed with `fe_sendauth: no password
  # supplied`. The seed asks `Rails.env.production?`; that is the only thing
  # that needs to answer differently, and the environment NAME must stay `test`
  # so the connection does not move.
  def seed_as_production!(admin_password: "a-long-real-password")
    allow(Rails.env).to receive(:production?).and_return(true)
    original = ENV.to_h
    ENV["ADMIN_PASSWORD"] = admin_password

    load Rails.root.join("db/seeds.rb")
  ensure
    ENV.replace(original)
  end

  # Everything that is neither reference nor config — the business tables a
  # production database must start empty.
  def business_models
    Rails.application.eager_load!

    ApplicationRecord.descendants.select { |model|
      model.table_exists? && !model.abstract_class? && model.name.present?
    } - REFERENCE_MODELS
  rescue StandardError
    []
  end

  before { seed_as_production! }

  describe "he can operate it" do
    # The one found by counting tables after a boot, having already checked
    # settings and moved on.
    it "has an admin who can open the console" do
      expect(AdminUser.count).to be >= 1
    end

    # Correction 13's premise: he retunes prices weekly from the console with
    # no deploy. A definition with no row is a number he cannot reach.
    it "has a row for every setting he is expected to tune" do
      missing = Setting::DEFINITIONS.keys - Setting.pluck(:key)

      expect(missing).to be_empty, "he cannot tune: #{missing.sort.join(', ')}"
    end

    it "has the taxonomy the app cannot run without" do
      expect(MerchantKind.count).to be >= 1
      expect(MerchantCategory.count).to be >= 1
      expect(PricingRate.count).to be >= 1
    end
  end

  # ── AND IT CONTAINS NOTHING FAKE ────────────────────────────────────────
  #
  # Correction 17 at the deployment layer. A production database that arrives
  # with demo restaurants in it is a shop he has to explain, or worse, one a
  # real customer can order from.
  describe "it contains nothing fake" do
    it "starts every business table empty, whatever tables those turn out to be" do
      populated = business_models.reject { |model| model.count.zero? }
                                 .map { |model| "#{model.name}=#{model.count}" }

      expect(populated).to be_empty, "sample data reached production: #{populated.join(', ')}"
    end

    # The derivation itself can fail silently — an empty model list would make
    # the example above pass by checking nothing. This is its floor.
    it "checked a meaningful number of tables" do
      expect(business_models.size).to be >= 10
      expect(business_models.map(&:name)).to include("Merchant", "User", "Order")
    end
  end
end
