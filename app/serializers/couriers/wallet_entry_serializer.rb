module Couriers
  # One ledger row, as the courier reads it.
  #
  # `balance_after` is included deliberately: a statement a courier can follow
  # line by line is what stops an argument about the balance, and it is already
  # stored rather than recomputed.
  class WalletEntrySerializer < ApplicationSerializer
    identifier :id

    fields :kind, :amount, :balance_after, :currency, :note, :created_at

    # The job it was charged against, if any — a top-up belongs to no job.
    field :job do |entry|
      next nil if entry.source.nil?

      { kind: entry.source.class.job_kind, code: entry.source.code }
    end
  end
end
