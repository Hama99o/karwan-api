module Couriers
  # A cash count, as the courier sees it.
  #
  # BOTH numbers are shown — expected and counted — along with the name of
  # whoever counted. A courier who is told only the variance cannot check it,
  # and "unexplained mismatches are theft" only works if both sides can see
  # the same two figures.
  class SettlementSerializer < ApplicationSerializer
    identifier :id

    fields :expected_amount, :counted_amount, :currency, :counted_by_name, :settled_at, :note

    field :variance do |settlement|
      settlement.variance
    end

    field :balanced do |settlement|
      settlement.balanced?
    end

    field :short do |settlement|
      settlement.short?
    end
  end
end
