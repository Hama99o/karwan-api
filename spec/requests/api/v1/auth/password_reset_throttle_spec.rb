require "rails_helper"

# PASSWORD RESET, LIMITED PER IDENTIFIER, WITH THE ADDRESS AS A BACKSTOP.
#
# It was 20 an hour per IP: the 21st person on one carrier network in an hour
# to forget a password was refused. The SMS bill is incurred per NUMBER, so
# the per-identifier limit (equal to OtpVerification's per-phone limits, from
# the same Settings) caps what costs money. Hamma9901's decision, 25 Sept 2026.
RSpec.describe "Password reset, throttled", type: :request do
  let(:nat) { { "REMOTE_ADDR" => "203.0.113.7" } }

  def reset(identifier) = post("/api/v1/auth/password_reset", params: { identifier: identifier }, headers: nat)
  def json = JSON.parse(response.body)

  around { |example| travel_to(Time.utc(2026, 9, 25, 10, 0, 3)) { example.run } }

  it "lets a district behind one carrier address reset, one each" do
    people = Array.new(40) { |i| create(:user, phone: "+9370040#{i.to_s.rjust(4, '0')}") }

    people.each do |person|
      reset(person.phone)
      expect(response).to have_http_status(:ok), "#{person.phone} was refused: #{response.body}"
    end
  end

  it "refuses the fourth request for one number inside the burst window, and says how long" do
    create(:user, phone: "+93700001234")
    3.times { reset("+93700001234") }
    expect(response).to have_http_status(:ok)

    reset("0700001234")

    expect(response).to have_http_status(:too_many_requests)
    expect(json).to eq("error" => "too many requests", "code" => "rate_limited",
                       "retry_after_seconds" => 15.minutes.to_i - 3)
  end

  it "sends no more codes than the per-phone limit allows" do
    create(:user, phone: "+93700001234")

    expect { 6.times { reset("+93700001234") } }.to change(OtpVerification, :count).by(3)
  end

  # Not an existence oracle: the counter is keyed on what was typed.
  it "answers a real number and an unused one in exactly the same words" do
    create(:user, phone: "+93700001234")
    answers = %w[+93700001234 +93700009876].map do |identifier|
      Array.new(4) { reset(identifier); [ response.status, response.body, response.headers["Retry-After"] ] }
    end

    expect(answers.first).to eq(answers.last)
    expect(answers.first.last.first).to eq(429)
  end

  it "does not touch somebody else on the same address" do
    create(:user, phone: "+93700001234")
    4.times { reset("+93700001234") }

    reset("+93700005678")

    expect(response).to have_http_status(:ok)
  end
end
