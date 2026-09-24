require "rails_helper"

# ═══ §5-B ON A SCREEN, WHICH IS THE HALF THAT WAS MISSING ══════════════════
#
# `TRUST_AND_REPUTATION.md` §5-B: *"cancellation reasons should be tracked per
# restaurant, so a restaurant cancelling a fifth of its orders is **visible
# before its customers leave**."* The counting is only half of that. A figure
# nothing renders is the failure `docs/NOTES.md` records from edu-safi — *"the
# correct scope existed, was correct, and was never called."*
#
# ── ASSERTING VALUES, NOT LABELS ──────────────────────────────────────────
#
# Every expectation here is on a NUMBER or a NAME that had to be computed.
# `docs/NOTES.md` records a console check that searched for a field's LABEL and
# passed against an empty cell, because the method sat below `private` and
# Administrate rendered the row with nothing in it. A 200 says the page
# rendered; it says nothing about what is on it.
RSpec.describe "which shop to ring", type: :request do
  let(:admin) { AdminUser.create!(name: "Ops", email: "ring@karwan.af", password: "a-long-test-password") }
  let(:owner) { create(:user, :merchant_owner) }

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  def refused!(merchant, reason: :out_of_stock)
    order = create(:order, :with_items, merchant: merchant, placed_at: 1.hour.ago)
    order.transition_to!(:rejected, actor: owner, actor_role: :merchant_owner)
    order.update!(rejection_reason: reason)
  end

  def delivered!(merchant)
    create(:order, :with_items, :delivered, merchant: merchant,
                                            placed_at: 1.hour.ago, delivered_at: 30.minutes.ago)
  end

  # Four lost out of ten is the document's own "a fifth" made concrete and
  # arguable — a rate a reader can check against the counts beside it.
  def struggling_shop!(name: "کباب شهر نو")
    shop = create(:merchant, name: name)
    4.times { refused!(shop) }
    6.times { delivered!(shop) }
    shop
  end

  describe "the reports page" do
    it "names the shop and states the rate with its denominator" do
      shop = struggling_shop!

      get "/admin/reports"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(shop.name),
                               "the name is the actionable part — he knows all ten personally"
      expect(response.body).to include("40.0%")
      expect(response.body).to include("4 of 10 orders"),
                               "a rate without its denominator is unarguable, which is the one thing a report must not be"
    end

    # The three outcomes are three phone calls, and the page keeps them apart
    # for the same reason the platform table above it does.
    it "shows a shop that never answers apart from one that refuses" do
      shop = create(:merchant, name: "سیلنت کباب")
      3.times do
        order = create(:order, :with_items, merchant: shop, placed_at: 1.hour.ago)
        order.transition_to!(:rejected, actor: nil, actor_role: :admin,
                                        reason: "timed out in placed with no response")
        order.update!(rejection_reason: :no_answer)
      end
      5.times { delivered!(shop) }

      get "/admin/reports"
      row = response.body[/#{Regexp.escape(shop.name)}.*?<\/tr>/m]

      expect(row).to be_present, "the shop is not on the page at all"
      expect(row).to include("37.5%")
      # Three in the "never answered" column and none in "refused".
      expect(row.scan(/<td>(\d+)<\/td>/).flatten).to eq(%w[0 3 0]),
                                                     "a tablet nobody watches is being reported as a shop that keeps saying no"
    end

    it "says so plainly when no shop lost anything" do
      shop = create(:merchant, name: "خوب کباب")
      8.times { delivered!(shop) }

      get "/admin/reports"

      expect(response.body).to include("delivered what it was sent"),
                               "an absent section reads as 'not measured', which is the opposite of the finding"
      expect(response.body).not_to include(shop.name)
    end

    # A page of shops with nothing wrong is a page nobody reads, and one bad
    # evening at a new shop is not a reason to spend a relationship.
    # ── AN ABSENCE ONLY MEANS SOMETHING BESIDE A PRESENCE ──────────────────
    #
    # The first version of this example asserted only that the thin shop is
    # absent, and stayed GREEN when the whole section was deleted — planted and
    # measured. A negative assertion on a page proves nothing on its own,
    # because the commonest reason a name is missing is that nothing rendered.
    # So a shop that MUST be listed is built alongside it.
    it "leaves out a shop with too few orders while still listing one with enough" do
      thin = create(:merchant, name: "نوی کباب")
      refused!(thin)
      2.times { delivered!(thin) }
      listed = struggling_shop!(name: "پخوانی کباب")

      get "/admin/reports"

      expect(response.body).to include(listed.name), "the section did not render at all, so the absence below proves nothing"
      expect(response.body).not_to include(thin.name),
                                  "one bad evening at a new shop is not a reason to spend a relationship"
    end
  end

  describe "the shop's own console page" do
    it "carries the computed line, not an empty cell" do
      shop = struggling_shop!

      get "/admin/merchants/#{shop.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("40.0% of 10 orders"),
                               "the row renders and the figure is missing, which is what a page-opens sweep cannot see"
      expect(response.body).to include("4 refused (out of stock ×4)")
    end

    it "does not claim a record for a shop nobody has ordered from" do
      shop = create(:merchant, name: "تازه کباب")

      get "/admin/merchants/#{shop.id}"

      expect(response.body).to include("no orders in the last 30 days"),
                               "0% beside a shop nobody has ordered from is a claim the data cannot make"
    end
  end
end
