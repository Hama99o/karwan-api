require "rails_helper"

# ═══ ASK THE COURIER BEFORE ANYBODY DECIDES ═══════════════════════════════
#
# `MONEY_AND_SETTLEMENT.md` §9: *"Before a timeout takes a job away, the
# platform contacts the courier... ask, wait, then reassign."* Past pickup no
# timeout takes the job — it is flagged for a human — but nothing asked the
# courier either; the operator saw a red row and had to guess whether it was a
# flat battery or a theft.
#
# ── THE DISCRIMINATING INPUTS ─────────────────────────────────────────────
#
# - A job stuck in the KITCHEN (`preparing`) with a courier on it: the shop's
#   delay, not his — he must not be asked.
# - Several runs over one stuck job: he is asked ONCE, riding on the flag's
#   per-state dedup, not once a minute.
# - The switch off: nothing sent, because the app must know this notification
#   before it is sent one.
RSpec.describe Dispatch::JobTimeoutsJob do
  include ActiveJob::TestHelper

  let(:courier) { create(:user, :courier, phone: "+93700000123") }
  let(:client) { instance_double(Notifications::FcmClient) }
  let(:sent) { [] }

  before do
    Setting.find_or_initialize_by(key: "support_phone").update!(value: "+93700999000", value_type: :string)
    create(:device_token, user: courier, token: "courier-phone")
    allow(Notifications::FcmClient).to receive(:new).and_return(client)
    allow(client).to receive(:send_to) do |tokens, **options|
      sent << { tokens: tokens }.merge(options)
      Notifications::FcmClient::Result.new(delivered: tokens.size, failed: 0, status: :ok)
    end
  end

  def switch_on!
    Setting.find_or_initialize_by(key: "courier_check_in_enabled").update!(value: "true", value_type: :boolean)
  end

  def stuck(status, at_column)
    create(:order, :with_items, status, courier: courier).tap do |order|
      order.update_columns(at_column => 3.hours.ago, updated_at: 3.hours.ago)
    end
  end

  it "asks the courier once when a job goes overdue in his hands, however many runs find it" do
    switch_on!
    order = stuck(:picked_up, :picked_up_at)

    perform_enqueued_jobs do
      3.times do
        described_class.new.perform
        travel 1.minute
      end
    end

    expect(sent.size).to eq(1)
    expect(sent.first).to include(tokens: [ "courier-phone" ], title_key: "courier.check_in.title",
                                  body_key: "courier.check_in.body")
    expect(sent.first[:data]).to include(code: order.code, status: "picked_up")
    # A push carries identifiers, not content (a_push_carries_identifiers_not_content_spec):
    # the support number reaches the app through /public/app_config, not a push.
    expect(sent.first[:data]).not_to have_key(:support_phone)
    expect(AuditLog.where(action: "courier.checked_in", target: order)).to exist
  end

  it "does not ask him about a job stuck in the kitchen" do
    switch_on!
    stuck(:preparing, :preparing_at)

    perform_enqueued_jobs { described_class.new.perform }

    expect(sent).to be_empty
  end

  it "asks the driver of a ride stuck in progress" do
    switch_on!
    ride = create(:trip, :in_progress, courier: courier)
    ride.update_columns(in_progress_at: 5.hours.ago, updated_at: 5.hours.ago)

    perform_enqueued_jobs { described_class.new.perform }

    expect(sent.map { |s| s[:data][:kind] }).to eq([ Trip::JOB_KIND ])
  end

  it "sends nothing while the switch is off, and still flags the job for a human" do
    order = stuck(:picked_up, :picked_up_at)

    perform_enqueued_jobs { described_class.new.perform }

    expect(sent).to be_empty
    expect(AuditLog.where(action: "order.overdue", target: order)).to exist
  end
end
