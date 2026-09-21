# A shop's own earnings history.
#
# R19: *"merchants and couriers each need their own earnings view — weekly
# earnings, and how much they owe the platform. For a courier that is already
# the wallet balance; for a merchant, under Model A, the answer is normally
# nothing, because they are paid in cash at every pickup. What they want is a
# statement: sales, commission deducted, net received."*
#
# READ-ONLY, and there is no issue endpoint. Statements are issued on a schedule
# so that every shop's week is cut at the same boundary; letting a merchant
# trigger one would let two shops disagree about when a week ends, and letting
# them re-issue would defeat the snapshot.
class Api::V1::Merchants::StatementsController < Api::V1::Merchants::BaseController
  def index
    # `policy_scope`, not a filter written here. `verify_policy_scoped` refused
    # the first version, which read `current_merchant.statements` — correct
    # today and exactly the shape `docs/NOTES.md` records from edu-safi, where
    # the right scope existed and was never consulted. The rule belongs in the
    # policy so a second caller cannot forget it.
    statements = policy_scope(MerchantStatement).newest_first

    paginate_blue(Merchants::StatementSerializer, statements)
  end
end
