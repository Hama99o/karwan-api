# `travel_to` and friends. Rails ships them; RSpec does not include them by
# default, and the first spec to need one was the merchant's `today` figures —
# where the whole question is which day an order falls in.
#
# Frozen rather than drifting: `travel_to` stops the clock inside the block, so
# an example asserting a day boundary cannot pass because it happened to run at
# 09:00 and fail at 00:01. That is the seventh shape (a time-decaying subject)
# and this is the tool that removes it rather than mitigating it.
RSpec.configure do |config|
  config.include ActiveSupport::Testing::TimeHelpers
end
