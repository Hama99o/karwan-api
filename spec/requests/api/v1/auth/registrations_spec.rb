require "rails_helper"

# ── SIGNING UP, WHICH IS NOW A SEPARATE ACTION ────────────────────────────────
#
# Under OTP, registering and signing in were one endpoint: possessing the phone
# was the proof, so a new number created an account and a known one signed in.
# With a password they have to be two, and the reason is a money one — folding
# them together means a mistyped digit quietly registers a SECOND account, with
# its own wallet, instead of failing to sign in.
RSpec.describe "Api::V1::Auth::Registrations", type: :request do
  def json
    JSON.parse(response.body)
  end

  let(:password) { "a-long-enough-password" }

  def register(params = {})
    post "/api/v1/auth/registration",
         params: { phone: "0700000123", password: password }.merge(params)
  end

  describe "POST /api/v1/auth/registration" do
    it "creates the account and signs them straight in" do
      expect { register(name: "احمد کریمی", locale: "ps") }.to change(User, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json["token"]).to be_present
      expect(json.dig("user", "name")).to eq("احمد کریمی")
      expect(json.dig("user", "locale")).to eq("ps")
    end

    # NO VERIFICATION STEP AT ALL — no code, no emailed link. Hamma9900's call
    # ("for now no authentication"), and the assertion is here rather than only
    # in the doc because a later contributor adding a confirmation gate would
    # break the product decision, not a detail.
    it "issues a usable token immediately, with nothing to confirm" do
      register

      token = json["token"]
      get "/api/v1/customer/addresses", headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:ok)
    end

    # THE FORM AN AFGHAN USER TYPES: a local 0-prefixed number. Stored
    # normalised, so signing in later with either form finds the same person.
    it "normalises the number BEFORE it is stored, so both forms are one account" do
      register(phone: "0700000123")

      expect(User.last.phone).to eq("+93700000123")

      post "/api/v1/auth/session", params: { identifier: "+93700000123", password: password }
      expect(response).to have_http_status(:created)
    end

    # THE CHECK THAT HAS TO HAPPEN AFTER NORMALISING, not before. `0700000123`
    # and `+93700000123` are the same phone, and a uniqueness check on the raw
    # string would let the same person hold two accounts — which in a cash
    # business means two wallets and two credit lines.
    it "refuses a number already registered in ANOTHER form" do
      create(:user, phone: "+93700000123")

      expect { register(phone: "0700000123") }.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("already_registered")
    end

    it "says so plainly, because somebody registering must be told to sign in" do
      create(:user, phone: "+93700000123")

      register

      # Deliberately the OPPOSITE trade from the sign-in failure, which hides
      # existence. A registration form cannot both create an account and
      # conceal that one exists, and a user who is not told will try three more
      # times and give up.
      expect(json["error"]).to include("already has an account")
    end

    it "accepts an email and stores it downcased" do
      register(email: "Ahmad@Gmail.COM")

      expect(User.last.email).to eq("ahmad@gmail.com")
    end

    # ── THE DEVIATION, ASSERTED SO IT IS A DECISION AND NOT A GAP ────────────
    #
    # "Both identifiers unique" does not mean both required. Requiring an email
    # locks out the two cases the requirement itself names: a SIDELOADED APK
    # over Bluetooth or WhatsApp, whose owner may hold no Google account, and a
    # SHARED HANDSET whose Gmail is somebody's brother's. The app asks for
    # both; the API refuses neither.
    it "registers without an email at all" do
      expect { register(email: nil) }.to change(User, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(User.last.email).to be_nil
    end

    # ── WHY THE UNIQUE INDEX IS PARTIAL ─────────────────────────────────────
    #
    # Postgres treats NULLs as distinct in a unique index, so a plain index
    # would already allow many null emails — but an empty STRING is not null,
    # and two accounts saved with `email: ""` would collide on a plain index
    # and be refused for no reason a user could understand. `presence` in the
    # service plus `WHERE email IS NOT NULL` is what makes both true at once:
    # many accounts with no email, at most one per real address.
    it "lets a SECOND account exist with no email" do
      register(phone: "0700000123")
      expect { register(phone: "0700000124") }.to change(User, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(User.where(email: nil).count).to be >= 2
    end

    it "refuses an email that belongs to somebody else" do
      create(:user, phone: "+93700000999", email: "ahmad@gmail.com")

      expect { register(email: "ahmad@gmail.com") }.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("registration_invalid")
    end

    it "refuses an email that is not an address" do
      expect { register(email: "ahmad-at-gmail") }.not_to change(User, :count)

      expect(json["code"]).to eq("registration_invalid")
    end

    # EIGHT, not Devise's six: this password is the only thing between somebody
    # else and a wallet with credit in it, and on a shared handset the threat
    # is usually somebody who knows the person.
    it "refuses a password shorter than eight characters" do
      expect { register(password: "1234567") }.not_to change(User, :count)

      expect(json["code"]).to eq("registration_invalid")
      expect(json["error"]).to include("8")
    end

    it "refuses a missing password without a 500" do
      expect { register(password: nil) }.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "refuses a missing phone number" do
      expect { register(phone: nil) }.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("registration_invalid")
    end

    it "refuses a number that cannot be an Afghan mobile" do
      expect { register(phone: "12") }.not_to change(User, :count)

      expect(json["code"]).to eq("registration_invalid")
    end

    # EVERYONE STARTS AS A CUSTOMER, whichever door they came in by. Partner
    # roles are granted after a human looks — one by approval, one by being
    # handed a shop.
    it "grants customer and nothing else" do
      register

      expect(User.last.user_roles.pluck(:role)).to eq([ "customer" ])
    end

    it "does not let a registration ask itself into a partner role" do
      register(role: "courier")

      expect(User.last.user_roles.pluck(:role)).to eq([ "customer" ])
      expect(json.dig("user", "active_role")).to eq("customer")
    end

    # A RIDER WHO INSTALLS THE APP AND TAPS "SIGN IN AS PARTNER" lands on the
    # form, not on an error. Same payload shape as the sign-in refusal, because
    # the app renders one screen for both.
    it "answers a partner door with the application path" do
      register(role: "courier")

      expect(response).to have_http_status(:created)
      expect(json.dig("role_request", "code")).to eq("role_not_held")
      expect(json.dig("role_request", "apply_to")).to eq("/api/v1/courier/registration")
    end

    it "never issues an admin role through the public door" do
      register(role: "admin")

      expect(User.last.user_roles.pluck(:role)).to eq([ "customer" ])
      expect(json.dig("role_request", "code")).to eq("not_a_mobile_role")
    end

    # A SOFT-DELETED ACCOUNT HOLDS ITS NUMBER. `User.kept` is what the check
    # reads, so this asserts the deliberate choice: the number is refused
    # rather than recycled, because the old row still carries order history and
    # a wallet, and a second row on the same phone splits both.
    it "refuses a number whose account was deleted" do
      create(:user, phone: "+93700000123").discard!

      register

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
