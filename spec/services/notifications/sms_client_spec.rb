require "rails_helper"

# The one thing in v0 that costs money per unit.
RSpec.describe Notifications::SmsClient do
  around do |example|
    original = ENV["SMS_PROVIDER"]
    example.run
    ENV["SMS_PROVIDER"] = original
  end

  describe "choosing an adapter" do
    it "defaults to the log adapter, which costs nothing and sends nothing" do
      ENV.delete("SMS_PROVIDER")

      expect(described_class.provider).to eq("log")
      expect(described_class.adapter).to eq(Notifications::Sms::LogAdapter)
    end

    # Shipping with the log adapter must be a decision somebody made, not a
    # default nobody noticed — every user would wait for a code that never
    # arrives while the server looks perfectly healthy.
    it "says plainly that the default is NOT production ready" do
      ENV.delete("SMS_PROVIDER")

      expect(described_class).not_to be_production_ready
    end

    # THE important failure mode. A typo in an env var must not mean "nobody
    # can log in" while looking like "nothing happened".
    it "RAISES on an unknown provider rather than silently dropping the message" do
      ENV["SMS_PROVIDER"] = "twilioo"

      expect { described_class.deliver(to: "+93700000001", body: "x") }
        .to raise_error(described_class::UnknownProvider, /nobody receives a code/)
    end
  end

  describe "delivering" do
    it "reports the result, with the provider that handled it" do
      ENV.delete("SMS_PROVIDER")

      result = described_class.deliver(to: "+93700000001", body: "Karwan: your code is 123456")

      expect(result).to be_delivered
      expect(result.provider).to eq("log")
    end

    it "writes the message where a developer can read it" do
      ENV.delete("SMS_PROVIDER")
      expect(Rails.logger).to receive(:info).with(/code is 123456/)

      described_class.deliver(to: "+93700000001", body: "Karwan: your code is 123456")
    end
  end
end

# The FIRST thing anybody ever reads from this platform.
RSpec.describe Notifications::OtpSms do
  def set(key, value)
    Setting.find_or_initialize_by(key: key).update!(value: value, value_type: :string)
  end

  it "puts the code in the message" do
    expect(described_class.body(code: "123456")).to include("123456")
  end

  # The words live in Settings because an SMS has no device to translate it —
  # so Hamma9900 pastes the real Pashto in with no deploy.
  it "uses the Pashto template for a Pashto speaker" do
    set("otp_sms_body_ps", "کاروان: ستاسو کوډ %{code} دی")

    expect(described_class.body(code: "123456", locale: "ps")).to eq("کاروان: ستاسو کوډ 123456 دی")
  end

  it "uses the Dari template for a Dari speaker, including a region-suffixed tag" do
    set("otp_sms_body_fa", "کاروان: کد شما %{code}")

    expect(described_class.body(code: "654321", locale: "fa-AF")).to include("654321")
    expect(described_class.body(code: "654321", locale: "fa-AF")).to start_with("کاروان")
  end

  it "falls back to English for an unknown or missing locale" do
    set("otp_sms_body_en", "Karwan: your code is %{code}")

    expect(described_class.body(code: "111111", locale: nil)).to eq("Karwan: your code is 111111")
    expect(described_class.body(code: "111111", locale: "ur")).to eq("Karwan: your code is 111111")
  end

  # Copy pasted into the console without the placeholder would send a message
  # with no code in it, and nobody would notice until a user rang to say the
  # SMS was useless.
  it "refuses a template with no %{code} in it and sends something usable anyway" do
    set("otp_sms_body_ps", "کاروان ته ښه راغلاست")

    body = described_class.body(code: "999999", locale: "ps")

    expect(body).to include("999999")
  end

  it "falls back to English when a locale's template is blank" do
    set("otp_sms_body_ps", "")
    set("otp_sms_body_en", "Karwan: your code is %{code}")

    expect(described_class.body(code: "222222", locale: "ps")).to eq("Karwan: your code is 222222")
  end
end
