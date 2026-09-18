require "rails_helper"

# ═══ A SHOP'S HOURS HAD NO WAY IN ══════════════════════════════════════════
#
# `Customers::MerchantSerializer` has served `opening_hours` to the customer
# app since it was written, and **201 of 205 merchants had none** — the four
# that did were seeded. Not because the field was wrong: because
# `MerchantOpeningHour` had no dashboard, no route and no place on the
# merchant's show page, so nobody could enter any.
#
# PRODUCT.md settles where they should come from: **admin onboards
# restaurants**, and the shop does not edit its own identity in v0. So the
# console is the only possible source, and the missing write path is why the
# read path meant nothing.
#
# This drives the whole chain in one file, because each half is convincing
# alone and wrong: an operator can enter hours, and the customer's payload
# carries what they entered.
RSpec.describe "an operator can set a shop's opening hours", type: :request do
  let(:admin) do
    AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password")
  end

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  let!(:merchant) { create(:merchant, name: "Kabab House", is_open: true) }

  it "offers a form at all, which is what was missing" do
    get "/admin/merchant_opening_hours/new"

    expect(response).to have_http_status(:ok)
  end

  it "creates them, and they are reachable from the shop's own page" do
    expect {
      post "/admin/merchant_opening_hours", params: {
        merchant_opening_hour: {
          merchant_id: merchant.id, day_of_week: 6,
          opens_at: "09:00", closes_at: "22:00"
        }
      }
    }.to change(MerchantOpeningHour, :count).by(1)

    get "/admin/merchants/#{merchant.id}"
    expect(response.body).to match(/opening.hours/i),
                             "the shop's own page does not show its hours — an operator cannot find what they set"
  end

  # THE HALF THAT MAKES IT WORTH ANYTHING. A console form that writes rows no
  # customer ever sees is the same dead path in a new costume.
  it "reaches the customer's payload" do
    post "/admin/merchant_opening_hours", params: {
      merchant_opening_hour: {
        merchant_id: merchant.id, day_of_week: 6, opens_at: "09:00", closes_at: "22:00"
      }
    }

    get "/api/v1/public/merchants/#{merchant.id}"

    hours = JSON.parse(response.body).dig("merchant", "opening_hours")
    expect(hours).to be_present, "the customer still sees no hours for a shop that has them"
    expect(hours.first).to include("day_of_week" => 6, "opens_at" => "09:00", "closes_at" => "22:00")
  end

  # ── THE DATABASE MUST HOLD WHAT THE OPERATOR TYPED ──────────────────────
  #
  # The console-to-customer round trip above passes under ANY zone handling,
  # because the write and the read use the same one: type 08:00, store 03:30
  # UTC, read 08:00. Self-consistent and wrong. So it did not catch the real
  # defect, which was what the column MEANT.
  #
  # Rails puts `:time` in `time_zone_aware_types`, so a `t.time` column is read
  # through `Time.zone` — right for an instant, wrong for a shop's opening time,
  # which is a fact about a wall clock in Kabul rather than a moment. Setting
  # the app zone to Kabul made it visible: rows stored as 09:00 began reading as
  # **13:30**, telling a customer a shop opens four and a half hours late.
  #
  # This asserts the stored value, which is the only assertion that
  # discriminates — and it is what a SQL report, a raw console query or a second
  # service would read.
  it "stores the hour as wall-clock, not shifted into UTC" do
    post "/admin/merchant_opening_hours", params: {
      merchant_opening_hour: {
        merchant_id: merchant.id, day_of_week: 3, opens_at: "08:00", closes_at: "21:00"
      }
    }

    row = MerchantOpeningHour.connection.select_one(
      "SELECT opens_at, closes_at FROM merchant_opening_hours WHERE merchant_id = #{merchant.id}"
    )

    expect(row["opens_at"].to_s).to start_with("08:00"),
                                    "the database holds #{row['opens_at']} for an 08:00 opening — " \
                                    "`:time` is being treated as an instant rather than a wall clock"
    expect(row["closes_at"].to_s).to start_with("21:00")
  end

  # The model refuses it; the console must refuse it too rather than 500.
  it "refuses hours that close before they open" do
    expect {
      post "/admin/merchant_opening_hours", params: {
        merchant_opening_hour: {
          merchant_id: merchant.id, day_of_week: 1, opens_at: "22:00", closes_at: "09:00"
        }
      }
    }.not_to change(MerchantOpeningHour, :count)
  end

  # Advisory, and the console must not imply otherwise: `is_open` is the manual
  # toggle that decides whether orders are accepted. Setting hours is not
  # opening a shop.
  it "does not change whether the shop is accepting orders" do
    merchant.update!(is_open: false)

    post "/admin/merchant_opening_hours", params: {
      merchant_opening_hour: {
        merchant_id: merchant.id, day_of_week: 6, opens_at: "09:00", closes_at: "22:00"
      }
    }

    expect(merchant.reload.is_open).to be false
  end
end
