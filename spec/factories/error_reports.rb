# Built the way the subscriber writes one: already-redacted text only.
FactoryBot.define do
  factory :error_report do
    sequence(:fingerprint) { |n| "fingerprint#{n}" }
    error_class { "RuntimeError" }
    message { "boom near [redacted]" }
    backtrace { "app/services/pricing/quote.rb:12:in 'call'" }
    source { "application.action_dispatch" }
    severity { "error" }
    handled { false }
    occurrences { 1 }
    first_seen_at { Time.current }
    last_seen_at { Time.current }
  end
end
