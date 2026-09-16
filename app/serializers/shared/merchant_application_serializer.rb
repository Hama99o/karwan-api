module Shared
  # An application as the APPLICANT sees it: what they told us, and where it
  # stands. Deliberately not the merchant serializer — a commission rate, a
  # rejection reason and an owner id are ops data, and this row is not a shop
  # yet.
  class MerchantApplicationSerializer < ApplicationSerializer
    fields :id, :name, :phone, :landmark_note, :status

    field :merchant_kind_id do |merchant|
      merchant.merchant_kind_id
    end

    field :contact_name do |merchant|
      merchant.owner_name
    end

    field :submitted_at do |merchant|
      merchant.created_at
    end

    # WHETHER THERE IS ANYTHING LEFT TO DO. `lead` means nobody has called yet;
    # anything else means a human has this in hand, which is the only thing the
    # applicant needs to know and the difference between "we have your details"
    # and "we are working on it".
    field :waiting_for_a_call do |merchant|
      merchant.status_lead?
    end
  end
end
