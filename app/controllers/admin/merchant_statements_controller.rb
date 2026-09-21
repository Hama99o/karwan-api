module Admin
  # Statements, newest period first — the order an operator reads them in when a
  # shop rings up about last week's figures.
  class MerchantStatementsController < Admin::ApplicationController
    def scoped_resource
      super.includes(:merchant).newest_first
    end
  end
end
