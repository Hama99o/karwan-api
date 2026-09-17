require "rails_helper"

# TELLING AN APPLICANT WHAT WE DECIDED.
#
# The third use of one piece of push plumbing, and the one where a missing
# notification means somebody **waits forever for an approval nobody told them
# about.** A courier who has sent his tazkira and heard nothing assumes he was
# refused — and on the supply side, which is the scarce side, a courier we
# convinced and then lost is the most expensive kind of loss.
RSpec.describe Notifications::CourierReviewAlert do
  let(:admin) { AdminUser.create!(name: "Ops", email: "ops@karwan.af", password: "a-long-test-password") }
  let(:applicant) { create(:user, :customer) }
  let(:profile) do
    create(:courier_profile, user: applicant, full_name: "عبدالله رحیمی",
                             national_id_number: "1400-1234", guarantor_name: "نعیم",
                             guarantor_phone: "+93700000999")
  end

  # A stub client, because FCM is the outside world and no credentials are
  # wired on this project at all — `FcmClient` reports `:unconfigured` rather
  # than raising, which is a deployment state and not a failed alert.
  let(:client) { instance_double(Notifications::FcmClient) }
  let(:sent) { [] }

  before do
    allow(client).to receive(:send_to) do |tokens, **options|
      sent << { tokens: tokens }.merge(options)
      Notifications::FcmClient::Result.new(delivered: tokens.size, failed: 0, status: :ok)
    end
    create(:device_token, user: applicant, token: "device-1")
  end

  def deliver!
    described_class.new(profile.reload, client: client).deliver!
  end

  # ── THREE OUTCOMES, THREE MESSAGES ─────────────────────────────────────────
  #
  # "We need one more thing" and "we cannot accept you" are different sentences
  # with different consequences, which is the whole reason `needs_more` is its
  # own state.
  it "says he can start, when he can" do
    profile.update!(id_document: nil) if false
    profile.id_document.attach(io: StringIO.new("x"), filename: "id.jpg", content_type: "image/jpeg")
    profile.selfie.attach(io: StringIO.new("x"), filename: "me.jpg", content_type: "image/jpeg")
    profile.approve!(by: admin)

    deliver!

    expect(sent.last[:title_key]).to eq("courier.review.approved.title")
    expect(sent.last[:data][:status]).to eq("approved")
  end

  it "asks for more without calling it a refusal" do
    profile.ask_for_more!(by: admin, note: "تذکره خوانا نیست")

    deliver!

    expect(sent.last[:title_key]).to eq("courier.review.needs_more.title")
    expect(sent.last[:title_key]).not_to eq("courier.review.rejected.title")
    expect(sent.last[:data][:note]).to eq("تذکره خوانا نیست")
  end

  it "refuses plainly, with the reason a human wrote" do
    profile.reject!(by: nil, reason: "ضمانت‌کننده انکار کرد")

    deliver!

    expect(sent.last[:title_key]).to eq("courier.review.rejected.title")
    expect(sent.last[:data][:note]).to eq("ضمانت‌کننده انکار کرد")
  end

  # WHAT IS STILL WANTED travels with the notification, so it can say it rather
  # than only inviting him to open the app and guess. Field names, because the
  # server cannot write Pashto.
  # ── SENT AS JSON, ON PURPOSE ──────────────────────────────────────────────
  #
  # `FcmClient` runs every data value through `to_s`, because FCM's data map is
  # string-to-string. An array of symbols therefore arrives as the literal
  # `"[:id_document, :selfie]"` — Ruby inspect output the app would have to
  # parse as Ruby. This example is what caught that: it asserted strings, got
  # symbols, and the fix was in the payload rather than in the expectation.
  it "carries what is missing as JSON the app can actually read" do
    profile.ask_for_more!(by: admin)

    deliver!

    decoded = JSON.parse(sent.last[:data][:missing])
    expect(decoded).to include("id_document")
    expect(decoded).to all(be_a(String))
  end

  # And it survives the client's own stringification, which is where the Ruby
  # inspect output would have appeared.
  it "does not ship Ruby inspect output in a data value" do
    profile.ask_for_more!(by: admin)

    deliver!

    values = sent.last[:data].values.map(&:to_s)
    # A notification that shipped no data at all would satisfy "no inspect
    # output in a data value" by having no data values.
    expect(values).not_to be_empty, "no data values — the assertion below would be vacuous"
    expect(values).to all(satisfy { |v| !v.match?(/\A\[:/) })
  end

  it "says nothing at all for a state nobody decided" do
    expect(profile.verification_status).to eq("pending")

    expect(deliver!).to be_nil
    expect(sent).to be_empty
  end

  # An enforcement action a human takes for a reason they will convey
  # themselves. A push saying "you are suspended" and nothing more is worse
  # than a phone call.
  it "says nothing on a suspension" do
    profile.update!(verification_status: :suspended)

    expect(deliver!).to be_nil
  end

  describe "when there is nowhere to send it" do
    before { applicant.device_tokens.destroy_all }

    # AN APPLICANT WITH NO DEVICE IS A HUMAN FOLLOW-UP, not a bug: he needs a
    # phone call, and that has to be visible in the console rather than buried
    # in a log. "Did he ever get told" is the first question when somebody
    # complains.
    it "records that a human has to make the call" do
      allow(client).to receive(:send_to)
        .and_return(Notifications::FcmClient::Result.new(delivered: 0, failed: 0, status: :no_tokens))
      profile.ask_for_more!(by: admin)

      expect { deliver! }.to change { AuditLog.for_action("courier.review_notified").count }.by(1)

      log = AuditLog.for_action("courier.review_notified").newest_first.first
      expect(log.details["needs_human_contact"]).to be true
      expect(log.details["devices"]).to eq(0)
      expect(log.target).to eq(profile)
    end
  end

  describe "the review itself enqueues it" do
    # From the MODEL, because an approval can also come from a script or a
    # console session, and a courier told nothing assumes he was refused.
    it "enqueues on an approval" do
      profile.id_document.attach(io: StringIO.new("x"), filename: "id.jpg", content_type: "image/jpeg")
      profile.selfie.attach(io: StringIO.new("x"), filename: "me.jpg", content_type: "image/jpeg")

      expect { profile.approve!(by: admin) }
        .to have_enqueued_job(Notifications::CourierReviewAlertJob).with(profile.id)
    end

    it "enqueues when more is asked for" do
      expect { profile.ask_for_more!(by: admin) }
        .to have_enqueued_job(Notifications::CourierReviewAlertJob).with(profile.id)
    end

    it "enqueues on a rejection" do
      expect { profile.reject!(by: nil, reason: "no") }
        .to have_enqueued_job(Notifications::CourierReviewAlertJob).with(profile.id)
    end
  end
end
