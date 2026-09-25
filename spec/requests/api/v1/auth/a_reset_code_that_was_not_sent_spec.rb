require "rails_helper"

# THE API MUST NOT CLAIM A DELIVERY IT DID NOT MAKE (karwan-42, 25 Sept 2026).
#
# Password reset answered `sent: true, channel: "sms"` while the only SMS
# adapter writes to a log, so the app truthfully told a customer with no
# email "we have sent a code to your phone", and nothing came. `sent` now
# says whether the CHANNEL can reach a person. That is a fact about the
# channel, not the account, so a real number and an unknown one still get
# the same answer: no existence oracle.
RSpec.describe "A reset code that was not sent", type: :request do
  before { create(:user, phone: "+93700001234", email: "ahmad@example.com", password: "a-long-enough-password") }

  def ask(identifier)
    post "/api/v1/auth/password_reset", params: { identifier: identifier }
    JSON.parse(response.body)
  end

  it "does not claim an SMS was sent when only the log adapter is behind it" do
    expect(ask("+93700001234")).to eq("sent" => false, "channel" => "sms")
  end

  it "says the same for a number nobody uses, so it tells nobody who has an account" do
    expect(ask("+93700009876")).to eq(ask("+93700001234"))
  end

  it "says sent when a real gateway is behind SMS" do
    allow(Notifications::SmsClient).to receive(:production_ready?).and_return(true)

    expect(ask("+93700001234")).to eq("sent" => true, "channel" => "sms")
  end

  it "does not claim an email was sent through an SMTP server nobody configured" do
    allow(Rails.application.config.action_mailer).to receive(:delivery_method).and_return(:smtp)
    stub_const("ENV", ENV.to_h.except("SMTP_ADDRESS"))

    expect(ask("ahmad@example.com")).to eq("sent" => false, "channel" => "email")
  end

  it "says sent for email when mail can go out" do
    expect(ask("ahmad@example.com")).to eq("sent" => true, "channel" => "email")
  end
end
