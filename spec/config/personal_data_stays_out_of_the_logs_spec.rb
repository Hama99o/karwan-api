require "rails_helper"

# The request log records every parameter. Phones, a courier's national ID,
# the login identifier and one-time codes must not reach it (karwan-42's
# privacy pass, 25 Sept 2026). An order code must, because operators search
# the logs by it.
RSpec.describe "personal data stays out of the logs" do
  let(:filter) { ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters) }

  it "hides every phone, the national ID, the login identifier and a one-time code" do
    filtered = filter.filter(
      "phone" => "+93700000001", "customer_phone" => "+93700000002", "passenger_phone" => "+93700000003",
      "contact_person_phone" => "+93700000004", "guarantor_phone" => "+93700000005",
      "national_id_number" => "1401-1234-56789", "identifier" => "0700000001", "code" => "123456",
      "password" => "a-long-enough-password"
    )

    expect(filtered.values.uniq).to eq([ "[FILTERED]" ])
  end

  it "leaves what an operator searches by" do
    expect(filter.filter("order_code" => "KQA00010", "merchant_id" => "5", "reason" => "out_of_stock"))
      .to eq("order_code" => "KQA00010", "merchant_id" => "5", "reason" => "out_of_stock")
  end
end
