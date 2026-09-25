# A PAGE PAST THE END IS AN EMPTY PAGE, not a 500.
#
# Without this extra, Pagy raises OverflowError for `page[number]` beyond the
# last page, and nothing rescued it, so every paginated endpoint answered 500
# to a "load more" one page too far. That was found 25 Sept 2026 while keying
# the board's ETag on the resolved page.
#
# The mechanism is hatiwal-api's (config/initializers/pagy.rb, read per
# correction 15). The VALUE deliberately differs: Hatiwal uses `:last_page`,
# which answers an overflow with the last page's records again. The Karwan
# app appends pages as they arrive, so that would duplicate rows on screen.
# `:empty_page` returns no records and `next_page: nil`, which is what stops a
# "load more".
require "pagy/extras/overflow"

Pagy::DEFAULT[:overflow] = :empty_page
