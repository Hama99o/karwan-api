# Keeps the error table small: 30 days, at most 500 distinct errors. The disk
# on this box has run at 92-97%, and an unbounded error table is a second
# outage waiting. Scheduled daily in config/recurring.yml.
class PruneErrorReportsJob < ApplicationJob
  queue_as :default

  def perform
    ErrorReport.prune!
  end
end
