require "rails_helper"

# ═══ A PERSON CANCELLED THIS ORDER, AND THE CUSTOMER IS TOLD A MACHINE DID ═══
#
# `StatusTransition#system?` is `actor_id.nil?`, and its comment says why:
# *"A nil actor means the system did it — i.e. a timeout fired."*
#
# That sentence is true in `Dispatch::JobTimeoutsJob`, which passes `actor: nil`
# BECAUSE no person acted. It is false in `Admin::OrdersController`, which
# passes `actor: nil` because the person who acted is an **`AdminUser`** and
# `StatusTransition#actor` is `belongs_to class_name: User`. The console has an
# operator; it has nowhere to put them.
#
# So one nil carries two opposite meanings, and three readers cannot tell them
# apart:
#
#   `Orders::EndedReason`         → `ended_by: "system"` on the customer's order
#   `Customers::OrderSerializer`  → `by_system: true` on the customer's timeline
#   `Admin::ReportsController`    → the "never answered" bucket, by the same test
#
# ── WHY THIS IS NOT COSMETIC ──────────────────────────────────────────────
#
# The two answers send the customer to different places. *"Nobody at the shop
# answered"* means try another shop. *"Karwan cancelled this"* means there is a
# person who decided it and a number in the app to ring — `CLAUDE.md`: support
# is a human and the app must admit it. Telling them a machine did it removes
# the one thing they could act on.
#
# And it is a hole in an irreversible record. One-way door 3 is *"a timestamp
# per state transition... Record the actor too"*, and today **every console
# intervention records no actor at all.** `AuditLog` already solved this and
# says how, in a comment on the same problem: *"Two kinds of actor, because
# there are two kinds of answer to 'who did this': an app user or a staff
# member in the ops console."* The append-only table with the stronger claim on
# it has the weaker actor model.
#
# ── THE DISCRIMINATING INPUT IS IN THIS FILE ON PURPOSE ───────────────────
#
# Both endings are built here — an operator's and a machine's — because a fix
# that simply stopped saying `system` would pass a file containing only the
# first. `docs/TESTING.md`: an assertion is only worth what its alternatives
# cost it.
RSpec.describe "an operator is not the system", type: :request do
  let(:admin) { AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password") }
  let(:customer) { create(:user, :customer) }
  let(:merchant) { create(:merchant) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(customer).last}" } }

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  def customer_sees(order)
    get "/api/v1/customer/orders/#{order.id}", headers: auth
    expect(response).to have_http_status(:ok), "not the order payload at all: #{response.body[0, 160]}"
    JSON.parse(response.body)["order"]
  end

  # The operator's ending: a human decided it, from the console.
  def cancelled_by_the_operator
    order = create(:order, :ready, customer: customer, merchant: merchant)
    patch "/admin/orders/#{order.id}/cancel", params: { reason: "customer rang the office" }
    expect(order.reload.status).to eq("cancelled"), "the console did not cancel it"
    order
  end

  # The machine's ending: nobody acted, the clock did.
  def closed_by_the_timeout
    order = create(:order, customer: customer, merchant: merchant,
                           status: :placed, placed_at: 1.hour.ago)
    Dispatch::JobTimeoutsJob.perform_now
    expect(order.reload.status).to eq("rejected"), "the timeout job did not close it"
    order
  end

  it "names the operator as the one who ended it, not the system" do
    order = cancelled_by_the_operator

    expect(customer_sees(order)["ended_reason"]["ended_by"]).to eq("admin"),
                                                               "a person at Karwan cancelled this and the customer is told a machine did"
  end

  it "still names the system when the clock closed it and nobody acted" do
    order = closed_by_the_timeout

    expect(customer_sees(order)["ended_reason"]["ended_by"]).to eq("system")
  end

  # The second surface, and the one a customer reads while it is happening.
  it "does not mark an operator's step as by_system in the timeline" do
    order = cancelled_by_the_operator

    step = customer_sees(order)["timeline"].detect { |entry| entry["status"] == "cancelled" }
    expect(step["by_system"]).to be(false), "the timeline says a machine cancelled it"
  end

  it "still marks the timeout's step as by_system" do
    order = closed_by_the_timeout

    step = customer_sees(order)["timeline"].detect { |entry| entry["status"] == "rejected" }
    expect(step["by_system"]).to be(true)
  end

  # ── THE RECORD ITSELF, WHICH IS THE PART THAT CANNOT BE BACKFILLED ───────
  it "records WHICH operator moved it, the way AuditLog already does" do
    order = cancelled_by_the_operator
    transition = order.transitions.chronological.last

    expect(transition.to_status).to eq("cancelled")
    expect(transition.admin_user).to eq(admin),
                                     "the audit log knows who cancelled it and the transition log does not"
  end

  # ── AND ON THE OPERATOR'S OWN SCREEN ────────────────────────────────────
  #
  # Asserting the NAME, not the row. `docs/NOTES.md` records a console check
  # that searched for a field's LABEL and passed against an empty cell, because
  # a 200 says the page rendered and nothing about what is in it.
  it "shows which operator moved it on the order page" do
    order = cancelled_by_the_operator

    get "/admin/orders/#{order.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Najibullah"),
                             "the console does not say who cancelled it, on the page an operator opens to find out"
  end

  it "refuses to delete a staff account that is somebody's answer to who did it" do
    order = cancelled_by_the_operator

    expect(admin.destroy).to be(false), "deleting the operator would blank the actor on an append-only history"
    expect(order.transitions.chronological.last.reload.admin_user).to eq(admin)
  end

  it "leaves both actors empty when a machine acted, which is what system means" do
    transition = closed_by_the_timeout.transitions.chronological.last

    expect(transition.actor).to be_nil
    expect(transition.admin_user).to be_nil
    expect(transition).to be_system
  end
end
