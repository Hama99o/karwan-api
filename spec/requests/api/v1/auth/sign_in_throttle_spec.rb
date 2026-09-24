require "rails_helper"

# SIGN-IN IS LIMITED PER ACCOUNT NAME, WITH THE ADDRESS AS A BACKSTOP.
#
# It was 120 attempts an hour per IP. A mobile carrier in Afghanistan puts a
# whole district behind one address, so the 121st real person on that network
# in an hour was refused because of other people's typos — on the evening a
# campaign video goes out, that is the evening it happens. Hamma9900's
# decision via Hamma9901, 25 Sept 2026: per identifier, backstop per IP, the
# refusal says how long, and it must not tell a real account from a missing one.
RSpec.describe "Signing in, throttled", type: :request do
  let(:password) { "a-long-enough-password" }
  let(:nat) { { "REMOTE_ADDR" => "203.0.113.7" } }

  def sign_in(identifier, pass, headers: nat)
    post "/api/v1/auth/session", params: { identifier: identifier, password: pass }, headers: headers
  end

  def json = JSON.parse(response.body)

  around { |example| travel_to(Time.utc(2026, 9, 25, 10, 0, 3)) { example.run } }

  # ── THE REPRODUCTION ──────────────────────────────────────────────────────
  it "lets a district behind one carrier address sign in, typos and all" do
    people = Array.new(130) { |i| create(:user, phone: "+9370020#{i.to_s.rjust(4, '0')}", password: password) }

    people.each do |person|
      sign_in(person.phone, "a typo")
      sign_in(person.phone, password)
      expect(response).to have_http_status(:created), "#{person.phone} was refused: #{response.body}"
    end
  end

  describe "one identifier" do
    let!(:user) { create(:user, phone: "+93700001234", password: password) }

    it "is refused after ten wrong passwords, and told how long to wait" do
      10.times { sign_in("+93700001234", "wrong") }
      expect(response).to have_http_status(:unprocessable_content)

      sign_in("+93700001234", "wrong")

      expect(response).to have_http_status(:too_many_requests)
      expect(json["code"]).to eq("rate_limited")
      # Windows are anchored to the UTC clock: 10:00:03 is 3 s into 10:00–10:15.
      # (Kabul is +4:30, so an hour window ends at half past, local.)
      expect(json["retry_after_seconds"]).to eq(15.minutes.to_i - 3)
      expect(response.headers["Retry-After"]).to eq((15.minutes.to_i - 3).to_s)
    end

    # Otherwise the throttle stops nobody who guesses well.
    it "refuses even the right password while the refusal stands" do
      10.times { sign_in("+93700001234", "wrong") }

      sign_in("+93700001234", password)

      expect(response).to have_http_status(:too_many_requests)
    end

    it "lets them in once the window has passed" do
      10.times { sign_in("+93700001234", "wrong") }

      travel 15.minutes
      sign_in("+93700001234", password)

      expect(response).to have_http_status(:created)
    end

    # A courier signing in on a phone and a tablet and a borrowed handset.
    it "does not count successful sign-ins" do
      15.times { sign_in("+93700001234", password) }

      expect(response).to have_http_status(:created)
    end

    # `0700…` and `+93700…` are one account to the lookup, so one counter.
    it "counts every spelling of the same number together" do
      5.times { sign_in("0700001234", "wrong") }
      5.times { sign_in("+93700001234", "wrong") }

      sign_in("+93 700 001 234", password)

      expect(response).to have_http_status(:too_many_requests)
    end

    it "does not touch anybody else on the same address" do
      create(:user, phone: "+93700005678", password: password)
      10.times { sign_in("+93700001234", "wrong") }

      sign_in("+93700005678", password)

      expect(response).to have_http_status(:created)
    end

    it "does not follow the person to another address — the account is what is guessed" do
      10.times { sign_in("+93700001234", "wrong") }

      sign_in("+93700001234", password, headers: { "REMOTE_ADDR" => "198.51.100.9" })

      expect(response).to have_http_status(:too_many_requests)
    end
  end

  # ── NOT AN EXISTENCE ORACLE ───────────────────────────────────────────────
  #
  # The counter is keyed on what was typed. If it only ran for real accounts,
  # the eleventh try would answer "does this number use Karwan?".
  it "refuses a real account and a missing one in exactly the same words" do
    create(:user, phone: "+93700001234", password: password)
    answers = %w[+93700001234 +93700009876].map do |identifier|
      bodies = Array.new(11) do
        sign_in(identifier, "wrong")
        [ response.status, response.body, response.headers["Retry-After"] ]
      end
      bodies
    end

    expect(answers.first).to eq(answers.last)
    expect(answers.first.last.first).to eq(429)
  end

  it "counts an email the same whether or not anybody owns it, in any case" do
    create(:user, phone: "+93700001234", email: "ahmad@example.com", password: password)

    10.times { sign_in("Ahmad@Example.com", "wrong") }
    sign_in("ahmad@example.com", password)
    owned = [ response.status, response.body ]

    10.times { sign_in("Nobody@Example.com", "wrong") }
    sign_in("nobody@example.com", password)

    expect([ response.status, response.body ]).to eq(owned)
    expect(response).to have_http_status(:too_many_requests)
  end

  # ── THE BACKSTOP ──────────────────────────────────────────────────────────
  #
  # One address spraying MANY identifiers, which no per-identifier counter can
  # see. It is set far above what a district signs in within an hour.
  it "still stops one address working through a list of numbers" do
    1_200.times { |i| sign_in("+9370030#{i.to_s.rjust(4, '0')}", "wrong") }
    expect(response).to have_http_status(:unprocessable_content)

    sign_in("+93700399999", "wrong")

    expect(response).to have_http_status(:too_many_requests)
    expect(json).to eq("error" => "too many requests", "code" => "rate_limited",
                       "retry_after_seconds" => 1.hour.to_i - 3)
  end

  # A limiter must never be why sign-in fails (see rate_limiting_spec).
  it "fails open on the identifier counter when the cache is gone" do
    create(:user, phone: "+93700001234", password: password)
    allow(RateLimitable.store).to receive(:increment).and_raise(StandardError, "cache is gone")
    allow(RateLimitable.store).to receive(:read).and_raise(StandardError, "cache is gone")

    sign_in("+93700001234", "wrong")
    expect(response).to have_http_status(:unprocessable_content)
    sign_in("+93700001234", password)

    expect(response).to have_http_status(:created)
  end
end
