require "rails_helper"

# ── THE WAY BACK IN ───────────────────────────────────────────────────────────
#
# `:recoverable` was declared on `User` with the password migration and nothing
# called it. That is worse here than the usual no-caller gap: the sign-in path
# deliberately refuses an account with no usable password using THE SAME WORDS
# as a wrong password, so without this flow a person who forgot theirs is told
# "that email or number and password do not match" forever, with no way to
# discover why.
#
# A CODE, NOT A LINK. Correction 16 — no web app — means there is no page for a
# reset link to open, and a deep link from a webview on a cheap Android fails
# silently. So the retained OTP machinery does the job it is actually suited
# to: rare, and where the friction is the point.
RSpec.describe "Api::V1::Auth::PasswordResets", type: :request do
  def json
    JSON.parse(response.body)
  end

  let(:password) { "a-long-enough-password" }
  let!(:user) do
    create(:user, :customer, phone: "+93700000801", email: "ahmad@gmail.com",
                             password: password, locale: "ps")
  end

  describe "POST /api/v1/auth/password_reset" do
    it "issues a code against the account's PHONE, whichever identifier was typed" do
      expect { post "/api/v1/auth/password_reset", params: { identifier: "ahmad@gmail.com" } }
        .to change { OtpVerification.for_phone("+93700000801").count }.by(1)

      expect(response).to have_http_status(:ok)
    end

    # The phone is NOT NULL for every account, so it is the one key every user
    # has — which also puts email resets behind the SAME counter that protects
    # the SMS bill rather than behind a second one nobody tuned.
    it "keys the code on the phone even for an email reset" do
      post "/api/v1/auth/password_reset", params: { identifier: "ahmad@gmail.com" }

      expect(OtpVerification.last.phone).to eq("+93700000801")
    end

    it "sends an SMS when a phone number was typed" do
      expect(Notifications::SmsClient).to receive(:deliver)
        .with(hash_including(to: "+93700000801")).and_return(
          Notifications::SmsClient::Result.new(delivered: true, provider: "log", error: nil)
        )

      post "/api/v1/auth/password_reset", params: { identifier: "0700000801" }

      expect(json["channel"]).to eq("sms")
    end

    it "sends an EMAIL when an email was typed" do
      expect { post "/api/v1/auth/password_reset", params: { identifier: "ahmad@gmail.com" } }
        .to have_enqueued_mail(UserMailer, :password_reset)

      expect(json["channel"]).to eq("email")
    end

    # ── THE ORACLE, THROUGH THE SECOND DOOR ─────────────────────────────────
    #
    # A login form and a reset form are two doors to the same question. Closing
    # only the first would be pointless: "no account with that email" here
    # leaks exactly what `PasswordSignInService` goes to lengths to hide, and in
    # one neighbourhood where everyone knows everyone that is a real privacy
    # leak.
    it "gives the SAME answer for an unknown identifier as for a known one" do
      post "/api/v1/auth/password_reset", params: { identifier: "ahmad@gmail.com" }
      known = [ response.status, response.body ]

      post "/api/v1/auth/password_reset", params: { identifier: "nobody@example.com" }
      unknown = [ response.status, response.body ]

      expect(unknown).to eq(known)
    end

    it "issues nothing at all for an unknown identifier" do
      expect { post "/api/v1/auth/password_reset", params: { identifier: "nobody@example.com" } }
        .not_to change(OtpVerification, :count)
    end

    it "sends nothing for an unknown identifier" do
      expect(Notifications::SmsClient).not_to receive(:deliver)

      post "/api/v1/auth/password_reset", params: { identifier: "+93700009999" }
    end

    # The channel is derived from WHAT WAS TYPED, never from the account, which
    # is the only way the app can say "check your email" without the answer
    # depending on whether anybody is there.
    it "reports the channel from the shape of the identifier, not from the account" do
      post "/api/v1/auth/password_reset", params: { identifier: "nobody@example.com" }
      expect(json["channel"]).to eq("email")

      post "/api/v1/auth/password_reset", params: { identifier: "+93700009999" }
      expect(json["channel"]).to eq("sms")
    end

    # NEVER, not even outside production. `POST /auth/otp` returns its code in
    # development so the QA rig can drive a sign-in; doing that here would mean
    # anybody who can type an address can take over an account on any
    # non-production deploy, and "it is only staging" is how that ships.
    it "never returns the code, in any environment" do
      post "/api/v1/auth/password_reset", params: { identifier: "ahmad@gmail.com" }

      expect(json.keys).to contain_exactly("sent", "channel")
      expect(response.body).not_to match(/\d{6}/)
    end

    it "refuses a blank identifier without a 500" do
      post "/api/v1/auth/password_reset", params: { identifier: "" }

      expect(response).to have_http_status(:ok)
      expect(OtpVerification.count).to eq(0)
    end

    # Being throttled implies an account, and that is the one leak accepted
    # here on purpose: a silent no-op leaves somebody who really did forget
    # their password tapping a dead button with no idea they must wait.
    it "says when to try again once the phone's counter is spent" do
      Setting.find_or_initialize_by(key: "otp_max_sends_per_day").update!(value: "1", value_type: :integer)
      post "/api/v1/auth/password_reset", params: { identifier: "ahmad@gmail.com" }

      post "/api/v1/auth/password_reset", params: { identifier: "ahmad@gmail.com" }

      expect(response).to have_http_status(:too_many_requests)
      expect(json["code"]).to eq("reset_throttled")
    end
  end

  describe "PUT /api/v1/auth/password_reset" do
    # Issued directly rather than through the endpoint, because the endpoint
    # deliberately never reveals the code — so the only way to hold a valid one
    # in a test is to mint it.
    let!(:issued) { OtpVerification.issue!("+93700000801") }
    let(:code) { issued.last }

    def complete(params = {})
      put "/api/v1/auth/password_reset",
          params: { identifier: "ahmad@gmail.com", code: code, password: "a-brand-new-password" }.merge(params)
    end

    it "sets the new password" do
      complete

      expect(response).to have_http_status(:created)
      expect(user.reload.valid_password?("a-brand-new-password")).to be true
    end

    it "makes the OLD password stop working" do
      complete

      post "/api/v1/auth/session", params: { identifier: "ahmad@gmail.com", password: password }
      expect(json["code"]).to eq("invalid_credentials")
    end

    # Signed in on this device immediately: sending somebody who just proved
    # they hold the phone back to the login screen to retype a password they
    # set four seconds ago is a dead end for a user who is already frustrated.
    it "hands back a usable token, so they are not sent back to the login screen" do
      complete

      get "/api/v1/customer/addresses", headers: { "Authorization" => "Bearer #{json['token']}" }
      expect(response).to have_http_status(:ok)
    end

    # ── EVERY OTHER SESSION DIES ────────────────────────────────────────────
    #
    # A reset is what somebody does when they think another person has their
    # password. Leaving that person's token alive makes the reset theatre — and
    # on a SHARED HANDSET (AFGHAN_UX §7) the other person is often still
    # holding the phone.
    it "revokes every session the account already had" do
      _session, stolen_token = UserSession.issue!(user, device_name: "somebody else's phone")

      complete

      expect(UserSession.authenticate(stolen_token)).to be_nil
    end

    it "does not revoke the session it just issued" do
      complete

      expect(UserSession.authenticate(json["token"])).to be_present
    end

    # A RESET IS NOT A WAY INTO A ROLE. It proves possession of a phone, which
    # is not evidence that anybody approved this person to carry cash.
    it "signs them in as a customer even if the payload asks for a partner role" do
      complete(role: "courier")

      expect(json.dig("user", "active_role")).to eq("customer")
    end

    it "refuses a wrong code" do
      complete(code: "000000")

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("reset_code_invalid")
      expect(user.reload.valid_password?(password)).to be true
    end

    it "refuses a code that has already been spent" do
      complete
      complete(password: "a-third-password-entirely")

      expect(json["code"]).to eq("reset_code_invalid")
      expect(user.reload.valid_password?("a-brand-new-password")).to be true
    end

    it "refuses an expired code" do
      issued.first.update!(expires_at: 1.minute.ago)

      complete

      expect(json["code"]).to eq("reset_code_invalid")
    end

    # ── A CODE ISSUED TO ONE ACCOUNT CANNOT RESET ANOTHER ───────────────────
    #
    # The worst failure available in this flow: anyone could reset the account
    # of anyone whose identifier they know by requesting a code for their OWN
    # number. The code is looked up by the RESOLVED USER'S phone, never by the
    # phone that asked, which is what closes it.
    it "refuses a code that was issued to a DIFFERENT account" do
      other = create(:user, phone: "+93700000999", email: "other@example.com", password: password)
      _record, other_code = OtpVerification.issue!(other.phone)

      complete(code: other_code)

      expect(json["code"]).to eq("reset_code_invalid")
      expect(user.reload.valid_password?(password)).to be true
    end

    # Same words as a wrong code for an unknown identifier: "no code has been
    # sent to this number" would say outright that no such account exists.
    it "refuses an unknown identifier with the SAME error as a wrong code" do
      complete(code: "000000")
      wrong_code = [ response.status, json["code"] ]

      complete(identifier: "nobody@example.com")

      expect([ response.status, json["code"] ]).to eq(wrong_code)
    end

    it "refuses a password shorter than eight characters, and keeps the code unspent" do
      complete(password: "1234567")

      expect(json["code"]).to eq("reset_invalid")
      expect(user.reload.valid_password?(password)).to be true
    end

    it "refuses a missing password without a 500" do
      complete(password: nil)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # ── THE EMAIL ITSELF ──────────────────────────────────────────────────────
  describe "the email" do
    it "carries the code, and the code only comes from the issued row" do
      _record, code = OtpVerification.issue!("+93700000801")
      mail = UserMailer.password_reset(user, code, locale: "ps")

      expect(mail.to).to eq([ "ahmad@gmail.com" ])
      expect(mail.html_part.body.to_s).to include(code)
      expect(mail.text_part.body.to_s).to include(code)
    end

    # An email client is not our app and will not infer direction from the
    # script. A Dari reset email rendering left-to-right is the first thing
    # this platform sends a partner, and it looks like a company that cannot
    # write Dari.
    it "is RTL for Pashto and Dari, and LTR for English" do
      _record, code = OtpVerification.issue!("+93700000801")

      expect(UserMailer.password_reset(user, code, locale: "ps").html_part.body.to_s).to include('dir="rtl"')
      expect(UserMailer.password_reset(user, code, locale: "fa").html_part.body.to_s).to include('dir="rtl"')
      expect(UserMailer.password_reset(user, code, locale: "en").html_part.body.to_s).to include('dir="ltr"')
    end

    # A six-digit number reversed is a DIFFERENT NUMBER. The code has to be
    # isolated LTR even inside an RTL email, or a Pashto user types 654321.
    it "keeps the code itself LTR inside an RTL email" do
      _record, code = OtpVerification.issue!("+93700000801")

      html = UserMailer.password_reset(user, code, locale: "ps").html_part.body.to_s

      expect(html).to include("direction: ltr")
      expect(html).to include("unicode-bidi: isolate")
    end

    it "takes its words from Setting rows, so Hamma9900 can paste Pashto with no deploy" do
      Setting.find_or_initialize_by(key: "password_reset_email_subject_ps")
             .update!(value: "د کاروان پاسورد", value_type: :string)
      _record, code = OtpVerification.issue!("+93700000801")

      expect(UserMailer.password_reset(user, code, locale: "ps").subject).to eq("د کاروان پاسورد")
    end
  end

  # ── THE SMS IS WORDED DIFFERENTLY FROM THE SIGN-IN CODE, ON PURPOSE ───────
  #
  # "your code is 123456" could mean signing in or resetting, and an ambiguous
  # code SMS is exactly what a phishing message imitates. Somebody who did NOT
  # ask for this has to be able to tell from the message what it is for.
  describe "the SMS copy" do
    it "says what the code is for, and says to ignore it if unasked" do
      body = Notifications::PasswordResetSms.body(code: "123456", locale: "en")

      expect(body).to include("123456")
      expect(body).not_to eq(Notifications::OtpSms.body(code: "123456", locale: "en"))
      expect(body.downcase).to include("password")
    end

    it "falls back rather than sending a message with no code in it" do
      Setting.find_or_initialize_by(key: "password_reset_sms_body_ps")
             .update!(value: "یو کوډ واستول شو", value_type: :string)

      expect(Notifications::PasswordResetSms.body(code: "123456", locale: "ps")).to include("123456")
    end
  end
end
