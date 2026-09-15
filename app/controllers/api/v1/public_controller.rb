# Guest-browsable endpoints: a merchant list, a catalog, a search.
#
# Deliberately separate from BaseController rather than a flag on it, so
# "this endpoint needs no login" is a visible choice in the class hierarchy
# rather than a parameter somebody can copy by accident.
#
# Correction 10: let them browse before they log in, and ask for the phone
# number at the cart. A login wall is where a first-time user with a cheap
# phone and a bad connection gives up — and every user here arrived through a
# conversation somebody had in person.
class Api::V1::PublicController < ApplicationController
  before_action :authenticate_optional!
end
