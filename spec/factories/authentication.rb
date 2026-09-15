FactoryBot.define do
  factory :otp_verification do
    sequence(:phone) { |n| "+9377#{n.to_s.rjust(7, '0')}" }
    # A known plaintext, so specs can assert both the success and failure paths
    # without reaching into the model to find out what the code was.
    code_digest { BCrypt::Password.create("123456") }
    expires_at { OtpVerification::TTL.from_now }
    attempts_count { 0 }

    trait :expired do
      expires_at { 1.minute.ago }
    end

    trait :consumed do
      consumed_at { Time.current }
    end

    trait :attempts_exhausted do
      attempts_count { OtpVerification::MAX_ATTEMPTS }
    end
  end

  factory :user_session do
    user
    sequence(:token_digest) { |n| UserSession.digest("token-#{n}") }
    expires_at { UserSession::TTL.from_now }
    last_used_at { Time.current }
    device_name { "Pixel 6a" }
    platform { "android" }

    trait :revoked do
      revoked_at { Time.current }
    end

    trait :expired do
      expires_at { 1.minute.ago }
    end
  end

  factory :device_token do
    user
    sequence(:token) { |n| "ExponentPushToken[dastarkhwan#{n}]" }
    platform { :android }
    active { true }
    last_seen_at { Time.current }
  end
end
