require "rails_helper"

# ═══ AFGHAN_UX §7: SESSIONS EXPIRE ═════════════════════════════════════════
#
# *"Sessions expire. Do not keep someone logged in forever on a device that
# isn't theirs."* And §7's premise, which is why it is in a design document
# rather than a security checklist: *"A phone in a household may be used by
# several people."*
#
# `scope :live` read `where(expires_at: [ nil, Time.current.. ])`, so a row with
# no expiry was live forever. `issue!` has always set one and nothing else
# creates a session, so no such row existed — **the possibility did**,
# uncommented, in a file where every other decision is argued at length.
RSpec.describe "a session cannot live forever" do
  let(:user) { create(:user, :customer) }

  it "always issues one with an expiry" do
    session, = UserSession.issue!(user)

    expect(session.expires_at).to be_present
    expect(session.expires_at).to be > Time.current
  end

  # THE COLUMN, not only the code path. A constraint is what makes the state
  # unreachable to an import, a console fix or a future migration — the three
  # ways every other "impossible" row in this repo has actually arrived.
  it "refuses to store one without an expiry" do
    expect {
      UserSession.create!(user: user, token_digest: UserSession.digest("x"), expires_at: nil)
    }.to raise_error(ActiveRecord::NotNullViolation)
  end

  it "declares the column NOT NULL" do
    expect(UserSession.columns_hash["expires_at"].null).to be(false),
                                                          "a session with no expiry is one that never expires"
  end

  it "drops out of `live` once it expires" do
    session, = UserSession.issue!(user)
    session.update_column(:expires_at, 1.second.ago)

    expect(UserSession.live).not_to include(session)
  end

  it "drops out of `live` when revoked, whatever its expiry" do
    session, = UserSession.issue!(user)
    session.update!(revoked_at: Time.current)

    expect(UserSession.live).not_to include(session)
  end

  # ── FAILS CLOSED ON BOTH SIDES ───────────────────────────────────────────
  #
  # The constraint makes a null unreachable; this asserts the SCOPE would
  # exclude one anyway. SQL answers a NULL comparison as unknown, so the row
  # falls OUT of `live` rather than into it — which is the direction that
  # matters, and the direction the old `[ nil, ... ]` branch inverted.
  it "would exclude a null expiry even if one existed" do
    live, = UserSession.issue!(user)

    sql = UserSession.live.to_sql
    expect(sql).to include("expires_at"), "the scope no longer filters on expiry at all"
    expect(sql).not_to match(/expires_at.*IS NULL/i),
                       "the scope still admits a null expiry, which is a session that never dies"
    expect(UserSession.live).to include(live), "plant a live session, or this proves nothing"
  end
end
