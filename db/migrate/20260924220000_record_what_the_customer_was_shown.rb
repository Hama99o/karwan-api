# What the customer's confirm screen said he would pay, beside what the order
# charges. Placement re-prices from scratch; a shop raising a price between
# the quote and the tap used to place at the new figure with nothing refused
# (518.56 shown, 768.56 placed). An increase is now refused; a decrease places
# at the lower figure — and this column is what lets the console see that the
# two differed at all. Nullable: an app build that sends no expected amount.
class RecordWhatTheCustomerWasShown < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :shown_amount_to_pay_in_cash, :decimal, precision: 12, scale: 2
  end
end
