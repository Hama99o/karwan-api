# The ledger, read-only. A balance can be recomputed from entries; entries can
# never be reconstructed from a balance.
module Admin
  class WalletEntriesController < Admin::ApplicationController
    def scoped_resource
      WalletEntry.includes(:courier_wallet, :recorded_by).newest_first
    end
  end
end
